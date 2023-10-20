// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:buildbucket/buildbucket_pb.dart' as bbv2;
import 'package:cocoon_service/ci_yaml.dart';
import 'package:gcloud/db.dart';
import 'package:meta/meta.dart';

import '../model/appengine/commit.dart';
import '../model/appengine/task.dart';
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

    final bbv2.PubSubCallBack pubSubCallBack = bbv2.PubSubCallBack.fromJson(message.data!);
    final List<int> userDataBytes = pubSubCallBack.userData;
    // user data from the message
    final String userDataString = String.fromCharCodes(userDataBytes);
    // build data from the message
    final bbv2.BuildsV2PubSub buildsV2PubSub = pubSubCallBack.buildPubsub;

    final bbv2.Build build = buildsV2PubSub.build;

    final Map<String, dynamic> userDataMap = json.decode(userDataString) as Map<String, dynamic>;

    // final BuildPushMessage buildPushMessage = BuildPushMessage.fromPushMessage(message);
    // log.fine('userData=${buildPushMessage.userData}');
    log.fine('userData=$userDataMap');
    // log.fine('Updating buildId=${buildPushMessage.build?.id} for result=${buildPushMessage.build?.result}');
    // Human readable status reason is available in summary_markdown.
    log.fine('Updating buildId=${build.id} for result=${build.status.name}');
    // if (buildPushMessage.userData.isEmpty) {
    if (userDataString.isEmpty) {
      log.fine('User data is empty');
      return Body.empty;
    }

    // final String? rawTaskKey = buildPushMessage.userData['task_key'] as String?;
    // final String? rawCommitKey = buildPushMessage.userData['commit_key'] as String?;

    final String? rawTaskKey = userDataMap['task_key'] as String?;
    final String? rawCommitKey = userDataMap['commit_key'] as String?;

    if (rawCommitKey == null) {
      throw const BadRequestException('userData does not contain commit_key');
    }
    // final Build? build = buildPushMessage.build;
    // if (build == null) {
    //   log.warning('Build is null');
    //   return Body.empty;
    // }

    final Key<String> commitKey = Key<String>(Key<dynamic>.emptyKey(Partition(null)), Commit, rawCommitKey);
    Task? task;
    if (rawTaskKey == null || rawTaskKey.isEmpty || rawTaskKey == 'null') {
      log.fine('Pulling builder name from parameters_json...');
      final Map<String, dynamic> buildParameters = build.infra.buildbucket.requestedProperties.fields;

      // log.fine(build.buildParameters);
      log.fine(buildParameters);
      // final String? taskName = build.buildParameters?['builder_name'] as String?;
      final String taskName = build.builder.builder;
      // final String taskName = buildParameters.containsKey('builder_name') ? buildParameters['build_name'] : null;
      if (taskName.isEmpty) {
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

    // We may need to update the task in the datastore.
    log.fine('Found $task');

    // task is something we define, in appengine.

    if (_shouldUpdateTask(build, task)) {
      final String oldTaskStatus = task.status;
      task.updateFromBuild(build);
      await datastore.insert(<Task>[task]);
      log.fine('Updated datastore from $oldTaskStatus to ${task.status}');
    } else {
      log.fine('skip processing for build with status scheduled or task with status finished.');
    }

    final Commit commit = await datastore.lookupByValue<Commit>(commitKey);
    final CiYaml ciYaml = await scheduler.getCiYaml(commit);
    final List<Target> postsubmitTargets = ciYaml.postsubmitTargets;
    if (!postsubmitTargets.any((element) => element.value.name == task!.name)) {
      log.warning('Target ${task.name} has been deleted from TOT. Skip updating.');
      return Body.empty;
    }
    final Target target = postsubmitTargets.singleWhere((Target target) => target.value.name == task!.name);
    if (task.status == Task.statusFailed ||
        task.status == Task.statusInfraFailure ||
        task.status == Task.statusCancelled) {
      log.fine('Trying to auto-retry...');
      final bool retried = await scheduler.luciBuildService.checkRerunBuilder(
        commit: commit,
        target: target,
        task: task,
        datastore: datastore,
      );
      log.info('Retried: $retried');
    }

    // Only update GitHub checks if target is not bringup
    if (target.value.bringup == false && config.postsubmitSupportedRepos.contains(target.slug)) {
      log.info('Updating check status for ${target.getTestName}');
      await githubChecksService.updateCheckStatus(
        buildPushMessage,
        scheduler.luciBuildService,
        commit.slug,
      );
    }

    return Body.empty;
  }

  // No need to update task in datastore if
  // 1) the build is `scheduled`. Task is marked as `In Progress`
  //    whenever scheduled, either from scheduler/backfiller/rerun. We need to update
  //    task in datastore only for
  //    a) `started`: update info like builder number.
  //    b) `completed`: update info like status.
  // 2) the task is already completed.
  //    The task may have been marked as completed from test framework via update-task-status API.
  // bool _shouldUpdateTask(Build build, Task task) {
  //   return build.status != Status.scheduled && !Task.finishedStatusValues.contains(task.status);
  // }


  // https://source.chromium.org/chromium/infra/infra/+/main:go/src/go.chromium.org/luci/buildbucket/proto/common.proto
  //
  // In the case of buildbucket v2 the status can be:
  // STATUS_UNSPECIFIED = 0;
  // Build was scheduled, but did not start or end yet.
  // SCHEDULED = 1;
  // Build/step has started.
  // STARTED = 2;
  // A build/step ended successfully.
  // This is a terminal status. It may not transition to another status.
  // SUCCESS = 12;  // 8 | ENDED
  // A build/step ended unsuccessfully due to its Build.Input,
  // e.g. tests failed, and NOT due to a build infrastructure failure.
  // This is a terminal status. It may not transition to another status.
  // FAILURE = 20;  // 16 | ENDED
  // A build/step ended unsuccessfully due to a failure independent of the
  // input, e.g. swarming failed, not enough capacity or the recipe was unable
  // to read the patch from gerrit.
  // start_time is not required for this status.
  // This is a terminal status. It may not transition to another status.
  // INFRA_FAILURE = 36;  // 32 | ENDED
  // A build was cancelled explicitly, e.g. via an RPC.
  // This is a terminal status. It may not transition to another status.
  // CANCELED = 68;  // 64 | ENDED
  bool _shouldUpdateTask(bbv2.Build build, Task task) {
    return build.status != bbv2.Status.SCHEDULED && !Task.finishedStatusValues.contains(task.status);
  }
}
