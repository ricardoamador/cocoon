import 'package:github/github.dart';
import 'package:revert/repository/revert_branch_name_format.dart';

import 'git_cli.dart';
import 'git_access_method.dart';

class RevertManager {
  final GitCli gitCli = GitCli(GitAccessMethod.HTTP);

  RevertManager();

  /// Allow us to revert a change for any repository but action is not processed
  /// if the repository is still being cloned. There is a possibility that the
  /// mutex could be locked even if checking the directory exists.
  Future<bool> revertChange(RepositorySlug slug, String workingDirectory, String commitSha,) async {
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