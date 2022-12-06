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

    final String cloneToFullPath = '$workingDirectory/${slug.name}_$commitSha';
    try {
      log.info('Attempting to clone ${slug.fullName} to $cloneToFullPath.');
      await repositoryManager.cloneRepository();
      log.info('Clone of ${slug.fullName} to $cloneToFullPath was successful.');
    } catch (e) {
      log.severe('Clone of ${slug.fullName} to $cloneToFullPath was NOT successful. Reason: $e');
      return false;
    }

    try {
      log.info('Attempting to revert $commitSha in ${slug.fullName}');
      await repositoryManager.revertCommit('main', commitSha);
      log.info('Revert of $commitSha in ${slug.fullName} was successful.');
    } catch (e) {
      log.severe('Revert of $commitSha in ${slug.fullName} was NOT successful. Reason: $e');
      return false;
    }

    return true;
  }
}
