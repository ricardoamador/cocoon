import 'dart:io';

import 'package:github/github.dart' as gh;
import 'package:revert/repository/command_strategy.dart';
import 'package:revert/repository/git_cli.dart';

class FakeGitCli extends GitCli {
  FakeGitCli(super.gitCloneMethod, super.cliCommand);

  bool _isGitRepo = false;
  bool _throwExp = false;

  late ProcessException _processException;
  late ProcessResult _processResult;

  set processException(ProcessException processException) => _processException = processException;
  set processResult(ProcessResult processResult) => _processResult = processResult;

  set isGitRepo(bool isGitRepo) => _isGitRepo = isGitRepo;
  set throwExp(bool throwExp) => _throwExp = throwExp;

  @override
  Future<bool> isGitRepository(String directory) async {
    if (_throwExp) {
      throw _processException;
    }
    return _isGitRepo;
  }

  @override
  Future<ProcessResult> cloneRepository({
    required gh.RepositorySlug slug,
    required String workingDirectory,
    required String targetDirectory,
    List<String>? options,
  }) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> setUpstream(
    gh.RepositorySlug slug,
    String branchName,
    String workingDirectory,
  ) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> fetchAll(String workingDirectory) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> pullRebase(String? workingDirectory) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> pullMerge(String? workingDirectory) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> createBranch({
    required String baseBranchName,
    required String newBranchName,
    CommandStrategy? createBranchStrategy,
    required String workingDirectory,
  }) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> revertChange({
    required String branchName,
    required String commitSha,
    CommandStrategy? revertCommitStrategy,
    required String workingDirectory,
  }) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> pushBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> deleteLocalBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return _handleCall();
  }

  @override
  Future<ProcessResult> deleteRemoteBranch(
    String branchName,
    String workingDirectory,
  ) async {
    return _handleCall();
  }

  Future<ProcessResult> _handleCall() async {
    if (_throwExp) {
      throw _processException;
    }
    return _processResult;
  }
}
