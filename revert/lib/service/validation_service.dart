// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:revert/exception/bigquery_exception.dart';
import 'package:revert/model/big_query_pull_request_record.dart';
import 'package:revert/model/big_query_revert_request_record.dart';
import 'package:revert/model/pull_request_change_type.dart';
import 'dart:async';

import 'package:revert/exception/retryable_merge_exception.dart';
import 'package:revert/requests/check_pull_request_queries.dart';
import 'package:revert/service/bigquery.dart';
import 'package:revert/service/config.dart';
import 'package:revert/service/github_service.dart';
import 'package:revert/service/graphql_service.dart';
import 'package:revert/service/log.dart';
import 'package:revert/service/process_method.dart';
import 'package:revert/service/revert_review_template.dart';
import 'package:revert/validations/revert.dart';
import 'package:github/github.dart' as github;
import 'package:graphql/client.dart' as graphql;
import 'package:retry/retry.dart';

import '../model/auto_submit_query_result.dart';
import '../request_handling/pubsub.dart';
import '../validations/approval.dart';
import '../validations/validation.dart';
import 'approver_service.dart';

/// Provides an extensible and standardized way to validate different aspects of
/// a commit to ensure it is ready to land, it has been reviewed, and it has been
/// tested. The expectation is that the list of validation will grow overtime.
class ValidationService {
  ValidationService(this.config, {RetryOptions? retryOptions})
      : retryOptions = retryOptions ?? Config.mergeRetryOptions {
    /// Validates a PR marked with the reverts label.
    revertValidation = Revert(config: config);
    approverService = ApproverService(config);

    validations.addAll({
      /// Validates the PR has been approved following the codereview guidelines.
      Approval(config: config),
    });
  }

  Revert? revertValidation;
  ApproverService? approverService;
  final Config config;
  final Set<Validation> validations = <Validation>{};
  final RetryOptions retryOptions;

  /// Processes a pub/sub message associated with PullRequest event.
  Future<void> processMessage(github.PullRequest messagePullRequest, String ackId, PubSub pubsub) async {
    final ProcessMethod processMethod = await processPullRequestMethod(messagePullRequest);

    switch (processMethod) {
      case ProcessMethod.processRevert:
        await processRevertRequest(
          config: config,
          result: await getNewestPullRequestInfo(config, messagePullRequest),
          messagePullRequest: messagePullRequest,
          ackId: ackId,
          pubsub: pubsub,
        );
        break;
      case ProcessMethod.doNotProcess:
        log.info('Should not process ${messagePullRequest.toJson()}, and ack the message.');
        await pubsub.acknowledge('auto-submit-queue-sub', ackId);
        break;
    }
  }

  /// Fetch the most up to date info for the current pull request from github.
  Future<QueryResult> getNewestPullRequestInfo(Config config, github.PullRequest pullRequest) async {
    final github.RepositorySlug slug = pullRequest.base!.repo!.slug();
    final graphql.GraphQLClient graphQLClient = await config.createGitHubGraphQLClient(slug);
    final int? prNumber = pullRequest.number;
    final GraphQlService graphQlService = GraphQlService();
    final Map<String, dynamic> data = await graphQlService.queryGraphQL(
      slug,
      prNumber!,
      graphQLClient,
    );
    return QueryResult.fromJson(data);
  }

  /// Checks if a pullRequest is still open and with autosubmit label before trying to process it.
  Future<ProcessMethod> processPullRequestMethod(github.PullRequest pullRequest) async {
    final github.RepositorySlug slug = pullRequest.base!.repo!.slug();
    final GithubService gitHubService = await config.createGithubService(slug);
    final github.PullRequest currentPullRequest = await gitHubService.getPullRequest(slug, pullRequest.number!);
    final List<String> labelNames = (currentPullRequest.labels as List<github.IssueLabel>)
        .map<String>((github.IssueLabel labelMap) => labelMap.name)
        .toList();

    if (currentPullRequest.state == 'closed' && labelNames.contains(Config.kRevertLabel)) {
      return ProcessMethod.processRevert;
    } else {
      return ProcessMethod.doNotProcess;
    }
  }

  /// The logic for processing a revert request and opening the follow up
  /// review issue in github.
  Future<void> processRevertRequest({
    required Config config,
    required QueryResult result,
    required github.PullRequest messagePullRequest,
    required String ackId,
    required PubSub pubsub,
  }) async {
    final ValidationResult revertValidationResult = await revertValidation!.validate(result, messagePullRequest);

    final github.RepositorySlug slug = messagePullRequest.base!.repo!.slug();
    final int prNumber = messagePullRequest.number!;
    final GithubService gitHubService = await config.createGithubService(slug);

    if (revertValidationResult.result) {
      // Approve the pull request automatically as it has been validated.
      await approverService!.revertApproval(result, messagePullRequest);

      final ProcessMergeResult processed = await processMerge(
        config: config,
        queryResult: result,
        messagePullRequest: messagePullRequest,
      );

      if (processed.result) {
        try {
          final RevertReviewTemplate revertReviewTemplate = RevertReviewTemplate(
            repositorySlug: slug.fullName,
            revertPrNumber: prNumber,
            revertPrAuthor: result.repository!.pullRequest!.author!.login!,
            originalPrLink: revertValidation!.extractLinkFromText(messagePullRequest.body)!,
          );

          final github.Issue issue = await gitHubService.createIssue(
            // Created issues are created and tracked within flutter/flutter.
            slug: github.RepositorySlug(Config.flutter, Config.flutter),
            title: revertReviewTemplate.title!,
            body: revertReviewTemplate.body!,
            labels: <String>['P1'],
            assignee: result.repository!.pullRequest!.author!.login!,
          );
          log.info('Issue #${issue.id} was created to track the review for pr# $prNumber in ${slug.fullName}');

          log.info('Attempting to insert a revert pull request record into the database for pr# $prNumber');
          await insertPullRequestRecord(
            config: config,
            pullRequest: messagePullRequest,
            pullRequestType: PullRequestChangeType.revert,
          );

          log.info('Attempting to insert a revert tracking request record into the database for pr# $prNumber');
          await insertRevertRequestRecord(
            config: config,
            revertPullRequest: messagePullRequest,
            reviewIssue: issue,
          );
        } on github.GitHubError catch (exception) {
          // We have merged but failed to create follow up issue.
          final String errorMessage = '''
An exception has occurred while attempting to create the follow up review issue for pr# $prNumber.
Please create a follow up issue to track a review for this pull request.
Exception: ${exception.message}
''';
          log.warning(errorMessage);
          await gitHubService.createComment(slug, prNumber, errorMessage);
        }
      } else {
        final String message = 'revert label is removed for ${slug.fullName}, pr#: $prNumber, ${processed.message}.';

        await removeLabelAndComment(
          githubService: gitHubService,
          repositorySlug: slug,
          prNumber: prNumber,
          prLabel: Config.kRevertLabel,
          message: message,
        );

        log.info(message);
      }
    } else if (!revertValidationResult.result && revertValidationResult.action == Action.IGNORE_TEMPORARILY) {
      // if required check runs have not completed process again.
      log.info('Some of the required checks have not completed. Requeueing.');
      return;
    } else {
      // since we do not temporarily ignore anything with a revert request we
      // know we will report the error and remove the label.
      final String commentMessage =
          revertValidationResult.message.isEmpty ? 'Validations Fail.' : revertValidationResult.message;

      await removeLabelAndComment(
        githubService: gitHubService,
        repositorySlug: slug,
        prNumber: prNumber,
        prLabel: Config.kRevertLabel,
        message: commentMessage,
      );

      log.info('revert label is removed for ${slug.fullName}, pr: $prNumber, due to $commentMessage');
      log.info('The pr ${slug.fullName}/$prNumber is not feasible for merge and message: $ackId is acknowledged.');
    }

    log.info('Ack the processed message : $ackId.');
    await pubsub.acknowledge('auto-submit-queue-sub', ackId);
  }

  /// Merges the commit if the PullRequest passes all the validations.
  Future<ProcessMergeResult> processMerge({
    required Config config,
    required QueryResult queryResult,
    required github.PullRequest messagePullRequest,
  }) async {
    final github.RepositorySlug slug = messagePullRequest.base!.repo!.slug();
    final int number = messagePullRequest.number!;

    try {
      // The createGitHubGraphQLClient can throw Exception on github permissions
      // errors.
      final graphql.GraphQLClient client = await config.createGitHubGraphQLClient(slug);
      graphql.QueryResult? result;

      await retryOptions.retry(
        () async {
          result = await _processMergeInternal(
            client: client,
            config: config,
            queryResult: queryResult,
            messagePullRequest: messagePullRequest,
          );
        },
        retryIf: (Exception e) => e is RetryableMergeException,
      );

      if (result != null && result!.hasException) {
        final String message = 'Failed to merge pr#: $number with ${result!.exception}';
        log.severe(message);
        return ProcessMergeResult(false, message);
      }
    } catch (e) {
      // Catch graphql client init exceptions.
      final String message = 'Failed to merge pr#: $number with ${e.toString()}';
      log.severe(message);
      return ProcessMergeResult(false, message);
    }

    return ProcessMergeResult.noMessage(true);
  }

  /// Remove a pull request label and add a comment to the pull request.
  Future<void> removeLabelAndComment({
    required GithubService githubService,
    required github.RepositorySlug repositorySlug,
    required int prNumber,
    required String prLabel,
    required String message,
  }) async {
    await githubService.removeLabel(repositorySlug, prNumber, prLabel);
    await githubService.createComment(repositorySlug, prNumber, message);
  }

  /// Insert a merged pull request record into the database.
  Future<void> insertPullRequestRecord({
    required Config config,
    required github.PullRequest pullRequest,
    required PullRequestChangeType pullRequestType,
  }) async {
    final github.RepositorySlug slug = pullRequest.base!.repo!.slug();
    final GithubService gitHubService = await config.createGithubService(slug);
    // We need the updated time fields for the merged request from github.
    final github.PullRequest currentPullRequest = await gitHubService.getPullRequest(slug, pullRequest.number!);

    log.info('Updated pull request info: ${currentPullRequest.toString()}');

    // add a record for the pull request into our metrics tracking
    PullRequestRecord pullRequestRecord = PullRequestRecord(
      organization: currentPullRequest.base!.repo!.slug().owner,
      repository: currentPullRequest.base!.repo!.slug().name,
      author: currentPullRequest.user!.login,
      prNumber: pullRequest.number!,
      prCommit: currentPullRequest.head!.sha,
      prRequestType: pullRequestType.name,
      prCreatedTimestamp: currentPullRequest.createdAt!,
      prLandedTimestamp: currentPullRequest.closedAt!,
    );

    log.info('Created pull request record: ${pullRequestRecord.toString()}');

    try {
      BigqueryService bigqueryService = await config.createBigQueryService();
      await bigqueryService.insertPullRequestRecord(
        projectId: Config.flutterGcpProjectId,
        pullRequestRecord: pullRequestRecord,
      );
      log.info('Record inserted for pull request pr# ${pullRequest.number} successfully.');
    } on BigQueryException catch (exception) {
      log.severe('Unable to insert pull request record due to: ${exception.toString()}');
    }
  }

  Future<void> insertRevertRequestRecord({
    required Config config,
    required github.PullRequest revertPullRequest,
    required github.Issue reviewIssue,
  }) async {
    final github.RepositorySlug slug = revertPullRequest.base!.repo!.slug();
    final GithubService gitHubService = await config.createGithubService(slug);
    // Get the updated revert issue.
    final github.PullRequest currentPullRequest = await gitHubService.getPullRequest(slug, revertPullRequest.number!);
    // Get the original pull request issue.
    String originalPullRequestLink = revertValidation!.extractLinkFromText(revertPullRequest.body)!;
    int originalPullRequestNumber = int.parse(originalPullRequestLink.split('#').elementAt(1));
    // return int.parse(linkSplit.elementAt(1));
    final github.PullRequest originalPullRequest = await gitHubService.getPullRequest(slug, originalPullRequestNumber);

    RevertRequestRecord revertRequestRecord = RevertRequestRecord(
      organization: currentPullRequest.base!.repo!.slug().owner,
      repository: currentPullRequest.base!.repo!.slug().name,
      author: currentPullRequest.user!.login,
      prNumber: revertPullRequest.number,
      prCommit: currentPullRequest.head!.sha,
      prCreatedTimestamp: currentPullRequest.createdAt,
      prLandedTimestamp: currentPullRequest.closedAt,
      originalPrAuthor: originalPullRequest.user!.login,
      originalPrNumber: originalPullRequest.number,
      originalPrCommit: originalPullRequest.head!.sha,
      originalPrCreatedTimestamp: originalPullRequest.createdAt,
      originalPrLandedTimestamp: originalPullRequest.closedAt,
      reviewIssueAssignee: reviewIssue.assignee!.login,
      reviewIssueNumber: reviewIssue.number,
      reviewIssueCreatedTimestamp: reviewIssue.createdAt,
    );

    try {
      BigqueryService bigqueryService = await config.createBigQueryService();
      await bigqueryService.insertRevertRequestRecord(
        projectId: Config.flutterGcpProjectId,
        revertRequestRecord: revertRequestRecord,
      );
      log.info('Record inserted for revert tracking request for pr# ${revertPullRequest.number} successfully.');
    } on BigQueryException catch (exception) {
      log.severe(exception.toString());
    }
  }
}

/// Small wrapper class to allow us to capture and create a comment in the PR with
/// the issue that caused the merge failure.
class ProcessMergeResult {
  ProcessMergeResult.noMessage(this.result);
  ProcessMergeResult(this.result, this.message);

  bool result = false;
  String? message;
}

/// Function signature that will be executed with retries.
typedef RetryHandler = Function();

/// Internal wrapper for the logic of merging a pull request into github.
Future<graphql.QueryResult> _processMergeInternal({
  required graphql.GraphQLClient client,
  required Config config,
  required QueryResult queryResult,
  required github.PullRequest messagePullRequest,
}) async {
  final String id = queryResult.repository!.pullRequest!.id!;

  final PullRequest pullRequest = queryResult.repository!.pullRequest!;
  final Commit commit = pullRequest.commits!.nodes!.single.commit!;
  final String? sha = commit.oid;
  final int number = messagePullRequest.number!;

  final graphql.QueryResult result = await client.mutate(
    graphql.MutationOptions(
      document: mergePullRequestMutation,
      variables: <String, dynamic>{
        'id': id,
        'oid': sha,
        'title': '${queryResult.repository!.pullRequest!.title} (#$number)',
      },
    ),
  );

  // We have to make this check because mutate does not explicitely throw an
  // exception, rather it wraps any exceptions encountered.
  if (result.hasException) {
    // This exception will bubble up if retries are exhausted.
    throw RetryableMergeException(result.exception!.graphqlErrors.first.message, result.exception!.graphqlErrors);
  }

  return result;
}