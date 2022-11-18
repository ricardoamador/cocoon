// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'package:github/github.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/service/log.dart';
class GitCloneManager {
  
  final GitCli _gitCli;

  GitCloneManager(this._gitCli);

  /// Clone the repository identified by the slug. 
  /// 
  /// A double checked locking mechanism is used here to guard across instances
  /// of this class attempting to clone the same repository.
  /// Note that thread safety is not guaranteed.
  Future<bool> cloneRepository(RepositorySlug slug, String workingDirectory,) async {
    // Use double checked locking, this is safe enough as reverts do not happen 
    // often enough that we would not be able to handle multiple requests.
    if (!_lockFileExists(slug, workingDirectory)) {
      _writeLockFile(slug, workingDirectory);
      if (_lockFileExists(slug, workingDirectory)) {
        final String targetCloneDirectory = '$workingDirectory/${slug.name}';
        // Remove the directory if the lock file has been deleted.
        if (Directory(targetCloneDirectory).existsSync()) {
          Directory(targetCloneDirectory).deleteSync(recursive: true);
        }
        final ProcessResult processResult = await _gitCli.cloneRepository(slug, workingDirectory);
        if (processResult.exitCode != 0) {
          log.severe('An error has occurred cloning repository ${slug.fullName} to dir $workingDirectory');
          log.info('${slug.fullName}, $workingDirectory: stdout: ${processResult.stdout}');
          log.info('${slug.fullName}, $workingDirectory: stderr: ${processResult.stderr}');
          return false;
        } else {
          log.info('${slug.fullName} was cloned successfully to dir $workingDirectory');
          _updateLocKFile(slug, workingDirectory);
          return true;
        }
      } else {
        log.warning('Unable to write repository lock file for ${slug.fullName}');
        return false;
      }
    } else {
      // Lock file exists and it is assumed the repository has been cloned.
      return true;
    }
  }

  /// Write the internal locking file to disk.
  void _writeLockFile(RepositorySlug slug, String workingDirectory) {
    final String targetLockFile = '$workingDirectory/${slug.name}.clone';
    try {
      if (! File(targetLockFile).existsSync()) {
        File(targetLockFile).createSync(exclusive: false);
      }
    } on FileSystemException {
      log.severe('Unable to create locking file $targetLockFile');
    }
  }

  /// Write the timestamp that the repository was cloned.
  void _updateLocKFile(RepositorySlug slug, String workingDirectory) {
    final String targetLockFile = '$workingDirectory/${slug.name}.clone';
    try {
      if (File(targetLockFile).existsSync()) {
        File(targetLockFile).writeAsStringSync('cloned:${DateTime.now().millisecondsSinceEpoch}');
      }
    } on FileSystemException {
      log.severe('Unable to update locking file $targetLockFile');
    }
  }

  /// Remove the clone lock file.
  /// 
  /// This is callable outside as this can be used to reset the repository if 
  /// any problems arise and intervention is needed.
  void removeLockFile(RepositorySlug slug, String workingDirectory) {
    final String targetLockFile = '$workingDirectory/${slug.name}.clone';
    try {
      if (File(targetLockFile).existsSync()) {
        File(targetLockFile).deleteSync();
      }
    } on FileSystemEntity {
      log.severe('Unable to remove locking file $targetLockFile');
    }
  }

  /// This allows callers to check if the repository represented by slug is
  /// ready for 
  Future<bool> isRepositoryReady(RepositorySlug slug, String workingDirectory) async {
    final String targetLockFile = '$workingDirectory/${slug.name}.clone';
    final String targetCloneDirectory = '$workingDirectory/${slug.name}';
    if (File(targetLockFile).existsSync()) {
      final bool fileNotEmpty = File(targetLockFile).readAsStringSync().isNotEmpty;
      final bool cloneDirExists = Directory(targetCloneDirectory).existsSync();
      final bool isGitRepo = await _gitCli.isGitRepository(targetCloneDirectory);
      return fileNotEmpty && cloneDirExists && isGitRepo;
    } else {
      return false;
    }
  }

  bool _lockFileExists(RepositorySlug slug, String workingDirectory) {
    final String targetLockFile = '$workingDirectory/${slug.name}.clone';
    return File(targetLockFile).existsSync();
  }
}
