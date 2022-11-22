// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:github/github.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_revert_branch_name.dart';
import 'package:revert/service/log.dart';

class GitRepositoryManager {
  final String workingDirectory;
  String? cloneToDirectory;
  final RepositorySlug slug;
  final GitCli gitCli;

  /// RepositoryManager will perform clone, revert and delete on the repository
  /// in the working directory that is cloned to [cloneToDirectory].
  ///
  /// If the clonedToDirectory is not provided then the name of the repository
  /// will be used as the cloneToDirectory.
  GitRepositoryManager({
    required this.slug,
    //path/to/working/directory
    required this.workingDirectory,
    //reponame_commitSha
    this.cloneToDirectory,
    required this.gitCli,
  }) {
    cloneToDirectory ??= slug.name;
  }

  /// Clone the repository identified by the slug.
  ///
  /// A double checked locking mechanism is used here to guard across instances
  /// of this class attempting to clone the same repository.
  /// Note that thread safety is not guaranteed.
  Future<bool> cloneRepository() async {
    final String targetCloneDirectory = '$workingDirectory/$cloneToDirectory';
    // Use double checked locking, this is safe enough as reverts do not happen
    // often enough that we would not be able to handle multiple requests.
    // final String targetCloneDirectory = '$workingDirectory/${slug.name}';
    // Remove the directory if the lock file has been deleted.
    if (Directory(targetCloneDirectory).existsSync()) {
      // Could possibly add a check for the slug in the remote url.
      if (!await gitCli.isGitRepository(targetCloneDirectory)) {
        Directory(targetCloneDirectory).deleteSync(recursive: true);
      } else {
        return true;
      }
    }

    // Checking out a sparse copy will not checkout source files but will still
    // allow a revert since we only care about the commitSha.
    final ProcessResult processResult = await gitCli.cloneRepository(
      slug: slug,
      workingDirectory: workingDirectory,
      targetDirectory: targetCloneDirectory,
      options: ['--sparse'],
    );

    if (processResult.exitCode != 0) {
      log.severe('An error has occurred cloning repository ${slug.fullName} to dir $workingDirectory');
      log.info('${slug.fullName}, $workingDirectory: stdout: ${processResult.stdout}');
      log.info('${slug.fullName}, $workingDirectory: stderr: ${processResult.stderr}');
      return false;
    } else {
      log.info('${slug.fullName} was cloned successfully to dir $workingDirectory');
      return true;
    }
  }

  /// Revert a commit in the current repository.
  ///
  /// The [baseBranchName] is the branch we want to branch from. In this case it
  /// will almost always be the default branch name. The target branch is
  /// preformatted with the commitSha.
  Future<void> revertCommit(String baseBranchName, String commitSha) async {
    final GitRevertBranchName revertBranchName = GitRevertBranchName(commitSha);
    // Working directory for these must be repo checkout directory.
    await gitCli.fetchAll(workingDirectory);
    await gitCli.pullRebase(workingDirectory);
    await gitCli.createBranch(
      baseBranchName: baseBranchName,
      newBranchName: revertBranchName.branch,
      workingDirectory: workingDirectory,
    );
    await gitCli.revertChange(
      branchName: revertBranchName.branch,
      commitSha: commitSha,
      workingDirectory: workingDirectory,
    );
    await gitCli.pushBranch(revertBranchName.branch, workingDirectory);
  }

  /// Delete the repository managed by this instance.
  Future<void> deleteRepository() async {
    final String targetCloneDirectory = '$workingDirectory/${slug.name}';
    if (Directory(targetCloneDirectory).existsSync()) {
      Directory(targetCloneDirectory).deleteSync(recursive: true);
    }
  }
}
