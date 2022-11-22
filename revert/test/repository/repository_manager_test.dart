import 'dart:io';

import 'package:github/github.dart';
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_repository_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Clone is successful', () {
    // final String workingDirectory = '${Directory.current.path}/test/repository';
    // final String targetRepo = '${Directory.current.path}/test/repository/flutter_test';
    // // final String repositoryLockFile = '$workingDirectory/flutter_test.clone';

    // final CliCommand cliCommand = CliCommand();
    // final GitCli gitCli = GitCli(GitAccessMethod.SSH, cliCommand);
    // final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
    // // final GitRepositoryManager gitCloneManager = GitRepositoryManager(slug, workingDirectory, gitCli);

    // test('Repository is not ready if GitCloneManager did not create it.', () async {
    //   await cliCommand.runCliCommand(
    //       executable: 'git', arguments: ['init', targetRepo], workingDirectory: workingDirectory);
    // });

    // test('Repository will get cloned over outside created repository.', () async {
    //   await cliCommand.runCliCommand(
    //       executable: 'git', arguments: ['init', targetRepo], workingDirectory: workingDirectory);
    //   await gitCloneManager.cloneRepository();
    // });

    // test('Clone repository is successful.', () async {
    //   await gitCloneManager.cloneRepository();
    // });

    // tearDown(() async {
    //   await cliCommand.runCliCommand(executable: 'rm', arguments: ['-rf', targetRepo]);
    // });
  });
}
