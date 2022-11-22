import 'dart:io';

import 'package:github/github.dart' as gh;
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_cli.dart';

import 'package:revert/repository/git_repository_manager.dart';
import 'package:revert/service/log.dart';
import 'git_access_method.dart';

class GitRevertFacilitator {
  GitRevertFacilitator();

  Future<bool> processRevertRequest(
    gh.RepositorySlug slug,
    String workingDirectory,
    GitAccessMethod gitAccessMethod,
    String commitSha,
  ) async {
    final GitRepositoryManager repositoryManager = GitRepositoryManager(
      slug: slug,
      //path/to/working/directory/
      workingDirectory: workingDirectory,
      //flutter_453a23
      cloneToDirectory: '${slug.name}_$commitSha',
      gitCli: GitCli(GitAccessMethod.SSH, CliCommand()),
    );

    try {
      await repositoryManager.cloneRepository();
    } catch (e) {
      log.severe('Repository was not ready or could not be cloned.');
      return false;
    }

    try {
      await repositoryManager.revertCommit('main', commitSha);
    } catch (e) {
      log.severe('Could not generate revert request for $commitSha');
    }

    return true;
  }
}
