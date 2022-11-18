// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:test/test.dart';

void main() {
  group('Testing git command locally', () {
    test('Checkout locally and push revert change to the repository.', () async {
      final String workingDirectory = '${Directory.current.path}/test/repository';
      final RepositorySlug repositorySlug = RepositorySlug('ricardoamador', 'flutter_test');

      final GitCli gitCli = GitCli(GitAccessMethod.SSH, CliCommand());
      final ProcessResult processResultClone = await gitCli.cloneRepository(repositorySlug, workingDirectory);
      expect(processResultClone.exitCode, isZero);

      const String branchName = 'ra_test';
      final String newWorkingDirectory = '$workingDirectory/flutter_test';
      final ProcessResult processResultNewBranch = await gitCli.createBranch(
          baseBranchName: 'main', newBranchName: branchName, workingDirectory: newWorkingDirectory);
      expect(processResultNewBranch.exitCode, isZero);

      final ProcessResult processResultFetchAll = await gitCli.fetchAll(newWorkingDirectory);
      expect(processResultFetchAll.exitCode, isZero);

      final ProcessResult processResultSetUpstream =
          await gitCli.setUpstream(repositorySlug, branchName, newWorkingDirectory);
      expect(processResultSetUpstream.exitCode, isZero);

      const String pullRequestSha = 'dd5a0ec86dfe257b323228058dde4198b2363ebc';
      final ProcessResult processResultCreateRevertChange = await gitCli.revertChange(
        branchName: branchName,
        commitSha: pullRequestSha,
        workingDirectory: newWorkingDirectory,
      );

      expect(processResultCreateRevertChange.exitCode, isZero);

      final ProcessResult processResultPushChange = await gitCli.pushBranch(branchName, newWorkingDirectory);
      expect(processResultPushChange.exitCode, isZero);
    });

    test('Delete missing dir', () {
      /// delete a non existing directory.
      try {
        Directory('${Directory.current.path}/testees').deleteSync(recursive: true);
      } catch (e) {
        /// No such file or directory.
      }
    });
  });
}
