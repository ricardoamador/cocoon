// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

import 'package:revert/cli/cli_command.dart';
import 'package:revert/exception/git_exception.dart';

import 'command_strategy.dart';
import 'git_clone_method.dart';

/// Class to wrap the command line calls to git.
class GitCli {
  Logger logger = Logger('RepositoryManager');

  static const String GIT = 'git';

  final String repositoryHttpPrefix = 'https://github.com/';
  final String repositorySshPrefix = 'git@github.com:';

  late String repositoryPrefix;

  GitCli(GitCloneMethod gitCloneMethod) {
    switch (gitCloneMethod) {
      case GitCloneMethod.SSH:
        repositoryPrefix = repositorySshPrefix;
        break;
      case GitCloneMethod.HTTP:
        repositoryPrefix = repositoryHttpPrefix;
        break;
    }
  }

  /// Check to see if the current directory is a git repository.
  Future<bool> isGitRepository(String directory) async {
    final ProcessResult processResult = await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['-C', directory, 'rev-parse', '2>/dev/null'],
      throwOnError: false,
    );
    return processResult.exitCode == 0;
  }

  /// Checkout repository if it does not currently exist on disk.
  /// We will need to protect against multiple checkouts just in case multiple
  /// calls occur at the same time.
  Future<ProcessResult> cloneRepository(RepositorySlug slug, String? workingDirectory) async {
    final ProcessResult processResult = await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['clone', '$repositoryPrefix${slug.fullName}'],
      workingDirectory: workingDirectory,
    );
    return processResult;
  }

  /// This is necessary with forked repos but may not be necessary with the bot
  /// as the bot has direct access to the repository.
  Future<ProcessResult> setUpstream(
    RepositorySlug slug,
    String branchName,
    String workingDirectory,
  ) async {
    await CliCommand.runCliCommand(
      executable: GIT,
      arguments: [
        'switch',
        branchName,
      ],
      workingDirectory: workingDirectory,
    );

    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: [
        'remote',
        'add',
        'upstream',
        '$repositoryPrefix${slug.fullName}',
      ],
      workingDirectory: workingDirectory,
    );
  }

  /// Fetch all new refs for the repository.
  Future<ProcessResult> fetchAll(String workingDirectory) async {
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['fetch', '--all'],
    );
  }

  Future<ProcessResult> pullRebase(String? workingDirectory) async {
    return _updateRepository(workingDirectory, '--rebase');
  }

  Future<ProcessResult> pullMerge(String? workingDirectory) async {
    return _updateRepository(workingDirectory, '--merge');
  }

  /// Run the git pull rebase command to keep the repository up to date.
  Future<ProcessResult> _updateRepository(
    String? workingDirectory,
    String pullMethod,
  ) async {
    final ProcessResult processResult = await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['pull', pullMethod],
      workingDirectory: workingDirectory,
    );
    return processResult;
  }

  /// Checkout and create a branch for the current edit.
  ///
  /// TODO The strategy may be unneccessary here as the bot will not have to
  /// create its own fork of the repo.
  Future<ProcessResult> createBranch({
    required String baseBranchName,
    required String newBranchName,
    CommandStrategy? createBranchStrategy,
    required String workingDirectory,
  }) async {
    // First switch to the baseBranchName.
    await CliCommand.runCliCommand(
      executable: GIT,
      arguments: [
        'switch',
        baseBranchName,
      ],
      workingDirectory: workingDirectory,
    );

    // Then create the new branch.
    createBranchStrategy ??= CommandStrategy([
      'checkout',
      '-b',
      newBranchName,
    ]);
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: createBranchStrategy.getCommandList,
      workingDirectory: workingDirectory,
    );
  }

  /// Revert a pull request commit.
  Future<ProcessResult> revertChange({
    required String branchName,
    required String commitSha,
    CommandStrategy? revertCommitStrategy,
    required String workingDirectory,
  }) async {
    // First switch to the base branch.
    await CliCommand.runCliCommand(
      executable: GIT,
      arguments: [
        'switch',
        branchName,
      ],
      workingDirectory: workingDirectory,
    );

    // Issue a revert of the pull request.
    revertCommitStrategy ??= CommandStrategy([
      'revert',
      '-m',
      '1',
      commitSha,
    ]);
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: revertCommitStrategy.getCommandList,
      workingDirectory: workingDirectory,
    );
  }

  /// Push changes made to the local branch to github.
  Future<ProcessResult> pushBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['push', '--verbose', '--progress', 'origin', branchName],
      workingDirectory: workingDirectory,
    );
  }

  /// Delete a local branch from the repo.
  Future<ProcessResult> deleteLocalBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['branch', '-D', branchName,],
      workingDirectory: workingDirectory,
    );
  }

  /// Delete a remote branch from the repo. 
  /// 
  /// When merging a pull request the pr branch is not automatically deleted. 
  Future<ProcessResult> deleteRemoteBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['push', 'origin', '--delete', branchName],
    );
  }
}
