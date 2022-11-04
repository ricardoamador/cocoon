// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:appengine/appengine.dart';
import 'package:revert/helpers.dart';
import 'package:revert/request_handling/authentication.dart';
import 'package:revert/request_handlers/collect_pull_requests_handler.dart';
import 'package:revert/request_handlers/github_webhook_handler.dart';
import 'package:revert/request_handlers/readiness_check_handler.dart';
import 'package:revert/request_handlers/update_revert_issues_handler.dart';
import 'package:revert/service/config.dart';
import 'package:revert/service/secrets.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:shelf_router/shelf_router.dart';

/// Number of entries allowed in [Cache].
const int kCacheSize = 1024;

Future<void> main() async {
  await withAppEngineServices(() async {
    useLoggingPackageAdaptor();

    final cache = Cache.inMemoryCacheProvider(kCacheSize);
    final Config config = Config(
      cacheProvider: cache,
      secretManager: CloudSecretManager(),
    );
    const CronAuthProvider authProvider = CronAuthProvider();

    final Router router = Router()
      ..post(
        // Receives calls from github to push revert requests to pubsub.
        '/webhook',
        GithubWebhookHandler(
          config: config,
        ).post,
      )
      // Revert pull requests.
      // ..get(
      //   '/revert',
      //   CheckPullRequest(
      //     config: config,
      //     cronAuthProvider: authProvider,
      //   ).run,
      // )
      ..get(
        '/check-pull-request',
        CollectPullRequestsHandler(
          config: config,
          cronAuthProvider: authProvider,
        ).run,
      )
      ..get(
        '/readiness_check',
        ReadinessCheckHandler(
          config: config,
        ).run,
      )
      ..get(
        // Update revert tracking review issue metrics.
        '/update-revert-issues',
        UpdateRevertIssuesHandler(
          config: config,
          cronAuthProvider: authProvider,
        ).run,
      );
    await serveHandler(router);
  });
}
