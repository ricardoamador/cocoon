// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Note that we need this file because Github does not expose a field within the
// checks that states whether or not a particular check is required or not.

import 'package:retry/retry.dart';
import 'package:revert/exception/retryable_exception.dart';
import 'package:github/github.dart' as github;
import 'package:revert/service/log.dart';

import '../service/github_service.dart';

const String ciyamlValidation = 'ci.yaml validation';

/// flutter, engine, cocoon, plugins, packages, buildroot and tests
//TODO (ricardoamador): make this configurable in the .github dir.
const Map<String, List<String>> requiredCheckRunsMapping = {
  'flutter': [ciyamlValidation],
  'engine': [ciyamlValidation],
  'cocoon': [ciyamlValidation],
  'plugins': [ciyamlValidation],
  'packages': [ciyamlValidation],
  'buildroot': [ciyamlValidation],
  'tests': [ciyamlValidation],
};

class ValidateCheckRuns {

  ValidateCheckRuns({
    RetryOptions? retryOptions,
  }) : retryOptions = retryOptions ?? const RetryOptions(
    delayFactor: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 5),
    maxAttempts: 5,
  );
  
  final RetryOptions retryOptions;

  /// Wait for the required checks to complete, and if repository has no checks
  /// true is returned.
  Future<bool> waitForRequiredChecks({
    required GithubService githubService,
    required github.RepositorySlug slug,
    required String sha,
  }) async {
    final List<github.CheckRun> targetCheckRuns = [];

    final List<String> checkRunNames = [];
    if (requiredCheckRunsMapping[slug.name] != null) {
      checkRunNames.addAll(requiredCheckRunsMapping[slug.name]!);
    }

    for (var element in checkRunNames) {
      targetCheckRuns.addAll(
        await githubService.getCheckRunsFiltered(
          slug: slug,
          ref: sha,
          checkName: element,
        ),
      );
    }

    bool checksCompleted = true;

    try {
      for (github.CheckRun checkRun in targetCheckRuns) {
        await retryOptions.retry(
          () async {
            await _verifyCheckRunCompleted(
              slug,
              githubService,
              checkRun,
            );
          },
          retryIf: (Exception e) => e is RetryableException,
        );
      }
    } catch (e) {
      log.warning('Required check has not completed in time. ${e.toString()}');
      checksCompleted = false;
    }

    return checksCompleted;
  }
}

/// Function signature that will be executed with retries.
typedef RetryHandler = Function();

/// Simple function to wait on completed checkRuns with retries.
Future<void> _verifyCheckRunCompleted(
  github.RepositorySlug slug,
  GithubService githubService,
  github.CheckRun targetCheckRun,
) async {
  final List<github.CheckRun> checkRuns = await githubService.getCheckRunsFiltered(
    slug: slug,
    ref: targetCheckRun.headSha!,
    checkName: targetCheckRun.name,
  );

  if (checkRuns.first.name != targetCheckRun.name || checkRuns.first.conclusion != github.CheckRunConclusion.success) {
    throw RetryableException('${targetCheckRun.name} has not yet completed.');
  }
}