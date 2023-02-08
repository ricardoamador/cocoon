// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:cocoon_service/ci_yaml.dart';
import 'package:gcloud/db.dart';
import 'package:github/github.dart';
import 'package:meta/meta.dart';

import '../model/appengine/commit.dart';
import '../model/appengine/task.dart';
import '../model/luci/push_message.dart';
import '../request_handling/body.dart';
import '../request_handling/exceptions.dart';
import '../request_handling/subscription_handler.dart';
import '../service/datastore.dart';
import '../service/logging.dart';
import '../service/github_checks_service.dart';
import '../service/scheduler.dart';

/// An endpoint for listening to build updates for postsubmit builds.
///
/// The PubSub subscription is set up here:
/// https://cloud.google.com/cloudpubsub/subscription/detail/luci-postsubmit?project=flutter-dashboard&tab=overview
///
/// This endpoint is responsible for updating Datastore with the result of builds from LUCI.
@immutable
class PostsubmitLuciSubscription extends SubscriptionHandler {
  /// Creates an endpoint for listening to LUCI status updates.
  const PostsubmitLuciSubscription({
    required super.cache,
    required super.config,
    super.authProvider,
    @visibleForTesting this.datastoreProvider = DatastoreService.defaultProvider,
    required this.scheduler,
    required this.githubChecksService,
  }) : super(subscriptionName: 'luci-postsubmit');

  final DatastoreServiceProvider datastoreProvider;
  final Scheduler scheduler;
  final GithubChecksService githubChecksService;

  @override
  Future<Body> post() async {
    final DatastoreService datastore = datastoreProvider(config.db);

    final BuildPushMessage buildPushMessage = BuildPushMessage.fromPushMessage(message);
    log.fine('userData=${buildPushMessage.userData}');
    log.fine('Updating buildId=${buildPushMessage.build?.id} for result=${buildPushMessage.build?.result}');
    if (buildPushMessage.userData.isEmpty) {
      log.fine('User data is empty');
      return Body.empty;
    }

    if (buildPushMessage.userData.containsKey('repo_owner') && buildPushMessage.userData.containsKey('repo_name')) {
      // Message is coming from a github checks api (postsubmit) enabled repo. We need to
      // create the slug from the data in the message and send the check status
      // update.

      final RepositorySlug slug = RepositorySlug(
        buildPushMessage.userData['repo_owner'] as String,
        buildPushMessage.userData['repo_name'] as String,
      );
      await githubChecksService.updateCheckStatus(
        buildPushMessage,
        scheduler.luciBuildService,
        slug,
      );
    }

    final String? rawTaskKey = buildPushMessage.userData['task_key'] as String?;
    final String? rawCommitKey = buildPushMessage.userData['commit_key'] as String?;
    if (rawCommitKey == null) {
      throw const BadRequestException('userData does not contain commit_key');
    }
    final Build? build = buildPushMessage.build;
    if (build == null) {
      log.warning('Build is null');
      return Body.empty;
    }
    final Key<String> commitKey = Key<String>(Key<dynamic>.emptyKey(Partition(null)), Commit, rawCommitKey);
    Task? task;
    if (rawTaskKey == null || rawTaskKey.isEmpty || rawTaskKey == 'null') {
      log.fine('Pulling builder name from parameters_json...');
      log.fine(build.buildParameters);
      final String? taskName = build.buildParameters?['builder_name'] as String?;
      if (taskName == null || taskName.isEmpty) {
        throw const BadRequestException('task_key is null and parameters_json does not contain the builder name');
      }
      final List<Task> tasks = await datastore.queryRecentTasksByName(name: taskName).toList();
      task = tasks.singleWhere((Task task) => task.parentKey?.id == commitKey.id);
    } else {
      log.fine('Looking up key...');
      final int taskId = int.parse(rawTaskKey);
      final Key<int> taskKey = Key<int>(commitKey, Task, taskId);
      task = await datastore.lookupByValue<Task>(taskKey);
    }
    log.fine('Found $task');

    task.updateFromBuild(build);
    await datastore.insert(<Task>[task]);
    log.fine('Updated datastore');

    if (task.status == Task.statusFailed || task.status == Task.statusInfraFailure) {
      log.fine('Trying to auto-retry...');
      final Commit commit = await datastore.lookupByValue<Commit>(commitKey);
      final CiYaml ciYaml = await scheduler.getCiYaml(commit);
      final Target target = ciYaml.postsubmitTargets.singleWhere((Target target) => target.value.name == task!.name);
      final bool retried = await scheduler.luciBuildService.checkRerunBuilder(
        commit: commit,
        target: target,
        task: task,
        datastore: datastore,
      );
      log.info('Retried: $retried');
    }

    return Body.empty;
  }
}
