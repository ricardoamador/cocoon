// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:revert/cli/cli_command.dart';
import 'package:revert/model/auto_submit_query_result.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:revert/repository/git_repository_manager.dart';
import 'package:revert/request_handling/pubsub.dart';
import 'package:revert/service/approver_service.dart';
import 'package:revert/service/config.dart';
import 'package:github/github.dart' as github;
import 'package:graphql/client.dart' as graphql;
import 'package:revert/service/github_service.dart';
import 'package:revert/service/graphql_service.dart';

class RevertService {
  Config config;
  ApproverService? approverService;
  late GitRepositoryManager gitCloneManager;
  late GitCli gitCli;

  RevertService(this.config) {
    approverService = ApproverService(config);
    gitCli = GitCli(GitAccessMethod.SSH, CliCommand());
    // gitCloneManager = RepositoryManager(gitCli);
  }

  /// Processes a pub/sub message associated with PullRequest event.
  Future<void> processMessage(github.PullRequest messagePullRequest, String ackId, PubSub pubsub) async {
    final github.RepositorySlug slug = messagePullRequest.base!.repo!.slug();
    final GithubService gitHubService = await config.createGithubService(slug);
    final github.PullRequest currentPullRequest = await gitHubService.getPullRequest(slug, messagePullRequest.number!);
    final List<String> labelNames = (currentPullRequest.labels as List<github.IssueLabel>)
        .map<String>((github.IssueLabel labelMap) => labelMap.name)
        .toList();

    // Pull request must be closed and merged with the revert label to automatically revert.
    if (currentPullRequest.state == 'closed' &&
        currentPullRequest.merged! &&
        labelNames.contains(Config.kRevertLabel)) {
      await processRevertRequest(
        config: config,
        result: await getNewestPullRequestInfo(config, messagePullRequest),
        messagePullRequest: messagePullRequest,
        ackId: ackId,
        pubsub: pubsub,
      );
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

  /// The logic for processing a revert request and opening the follow up
  /// review issue in github.
  Future<void> processRevertRequest({
    required Config config,
    required QueryResult result,
    required github.PullRequest messagePullRequest,
    required String ackId,
    required PubSub pubsub,
  }) async {
    // Two types of requests based on revert label can be handled
    // revert on a closed issue is to generate the revert commit and push it to github.
    //    bot will add another label to the newly opened pr 'bot-revert'

    // When we process the revert request we need to do the following:
    // 1. run git checkout to new directory.

    // 2. use the commit has from the pull request and revert that using git revert $sha.

    // 3. use git commit -m 'Revert message.'

    // 4. git push origin HEAD.

    // 5. open a pull request with the change branch.

    // 6. cleanup the disk.

    // 7. auto approve the pull request with the bot.

    // 8. merge the pull request.

    // 9. open the follow up review issue.

    // 10. notify the discrod tree-status channel.
  }

  void cloneRepository() {}

  void performCommit() {}

  void cleanupDisk() {}

  void openPullRequest() {}

  void approvePullRequest() {}

  void mergePullRequest() {}

  void openReviewIssue() {}

  void notifyDiscord() {}

  void recordRecord() {}
}
