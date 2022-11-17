// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:github/github.dart';
import 'package:mutex/mutex.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:revert/service/log.dart';

/// Singleton class to limit access to clonging a repository. We can allow
/// multiple repositories on disk but do not want multiples of the same
/// repository on the disk. This might be overkill as git will simply complain
/// if it attempts to clone into a non empty git directory.
class GitCloneManager {
  final Mutex _mutex = Mutex();
  // TODO the method needs to be passed through.
  final GitCli gitCli = GitCli(GitAccessMethod.HTTP);

  static final GitCloneManager _repositoryManager = GitCloneManager._internalConstructor();

  factory GitCloneManager() {
    return _repositoryManager;
  }

  GitCloneManager._internalConstructor();

  Future<bool> cloneRepository(RepositorySlug slug, String workingDirectory,) async {
    await _mutex.acquire();
    try{

      final String targetCloneDirectory = '$workingDirectory/${slug.name}';
      if (Directory(targetCloneDirectory).existsSync() && await gitCli.isGitRepository(targetCloneDirectory)) {
        return true;
      } else  {
        if (Directory(targetCloneDirectory).existsSync()) {
          Directory(targetCloneDirectory).deleteSync(recursive: true);
        }

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
}
