
import 'package:github/github.dart' as gh;
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_cli.dart';

import 'package:revert/repository/git_repository_manager.dart';
import 'git_access_method.dart';

class GitRevertFacilitator {
  GitRevertFacilitator();

  Future<void> processRevertRequest(
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
      gitCli: GitCli(gitAccessMethod, CliCommand()),
    );

    // final String cloneToFullPath = '$workingDirectory/${slug.name}_$commitSha';
    try {
      await repositoryManager.cloneRepository();
      await repositoryManager.revertCommit('main', commitSha);
    } finally {
      await repositoryManager.deleteRepository();
    }
  }
}
