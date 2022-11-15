// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:github/github.dart';
import 'package:logging/logging.dart';

import 'package:revert/cli/cli_command.dart';
import 'package:revert/service/config.dart';

import 'command_strategy.dart';

class RepositoryManager {
  Config config;
  RepositorySlug slug;

  Logger logger = Logger('RepositoryManager');

  static const String GIT = 'git';

  final String repositoryUrlPrefix = 'https://github.com/';

  RepositoryManager(this.config, this.slug);

  /// Checkout repository if it does not currently exist on disk.
  /// We will need to protect against multiple checkouts just in case multiple
  /// calls occur at the same time.
  Future<ProcessResult> cloneRepository(String? workingDirectory) async {
    final ProcessResult processResult = await CliCommand.runCliCommand(
      executable: GIT,
      arguments: ['clone', '$repositoryUrlPrefix${slug.fullName}'],
    );
    return processResult;
  }

  Future<ProcessResult> pullRebase(String? workingDirectory) async {
    return _updateRepository(workingDirectory, '--rebase');
  }

  Future<ProcessResult> pullMerge(String? workingDirectory) async {
    return _updateRepository(workingDirectory, '--merge');
  }

  /// git remote add upstream git@github.com:flutter/assets-for-api-docs
  Future<ProcessResult> setUpstream(
    String branchName,
    String? upStreamUrl,
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

    upStreamUrl ??= '$repositoryUrlPrefix${slug.fullName}';
    return await CliCommand.runCliCommand(
      executable: GIT,
      arguments: [
        'remote',
        'add',
        'upstream',
        upStreamUrl,
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
  Future<ProcessResult> revertChange(
    String branchName,
    String commitSha,
    CommandStrategy? revertCommitStrategy,
    String workingDirectory,
  ) async {
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
}
