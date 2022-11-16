// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:github/github.dart';
import 'package:mutex/mutex.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_clone_method.dart';
import 'package:revert/repository/revert_branch_name_format.dart';
import 'package:revert/service/log.dart';

/// Singleton class to limit access to clonging a repository. We can allow
/// multiple repositories on disk but do not want multiples of the same
/// repository on the disk. This might be overkill as git will simply complain
/// if it attempts to clone into a non empty git directory.
class RepositoryManager {
  final Mutex _mutex = Mutex();
  static final RepositoryManager _repositoryManager = RepositoryManager._internalConstructor();
  final GitCli gitCli = GitCli(GitCloneMethod.HTTP);

  factory RepositoryManager() {
    return _repositoryManager;
  }

  RepositoryManager._internalConstructor();

  /// Checkout the repository while blocking other calls attempting to do the
  /// same. We do not want multiple checkouts of the same directory.
  Future<bool> cloneRepository(RepositorySlug slug, String workingDirectory) async {
    await _mutex.acquire();
    try {
      if (Directory(workingDirectory).existsSync()) {
        return true;
      } else {
        final ProcessResult processResult = await gitCli.cloneRepository(slug, workingDirectory);
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
    } finally {
      _mutex.release();
    }
  }

  /// Allow for external callers to check to see if the mutex is locked or not
  /// so that we can simply avoid calling the checkoutRepository method.
  bool get isLocked => _mutex.isLocked;

  /// Allow us to revert a change for any repository but action is not processed
  /// if the repository is still being cloned. There is a possibility that the
  /// mutex could be locked even if checking the directory exists.
  Future<bool> revertChange(RepositorySlug slug, String workingDirectory, String commitSha) async {
    if (isLocked) {
      return false;
    } else {
      /// Any of these will throw an exception that can be accessed by the caller.
      await gitCli.fetchAll(workingDirectory);
      await gitCli.pullRebase(workingDirectory);
      final RevertBranchNameFormat newBranchName = RevertBranchNameFormat(commitSha);
      await gitCli.createBranch(
        baseBranchName: 'main',
        newBranchName: newBranchName.branch,
        workingDirectory: workingDirectory,
      );
      await gitCli.revertChange(
        branchName: newBranchName.branch,
        commitSha: commitSha,
        workingDirectory: workingDirectory,
      );
      await gitCli.pushBranch(
        newBranchName.branch,
        workingDirectory,
      );
      return true;
    }
  }
}
