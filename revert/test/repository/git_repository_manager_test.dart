import 'dart:io';

import 'package:github/github.dart';
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_repository_manager.dart';
import 'package:test/test.dart';

void main() {
  group('RepositoryManager', () {
    final String workingDirectoryOutside = Directory.current.parent.parent.path;

    final String workingDirectory = '${Directory.current.path}/test/repository';
    final String targetRepoCheckoutDirectory = '${Directory.current.path}/test/repository/flutter_test';
    final CliCommand cliCommand = CliCommand();
    final GitCli gitCli = GitCli(GitAccessMethod.SSH, cliCommand);
    final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');

    final GitRepositoryManager gitCloneManager = GitRepositoryManager(
      slug: slug,
      workingDirectory: workingDirectoryOutside,
      cloneToDirectory: 'flutter_test',
      gitCli: gitCli,
    );

    test('cloneRepository()', () async {
      final bool isSuccessful = await gitCloneManager.cloneRepository();
      expect(isSuccessful, isTrue);
      expect(Directory('$workingDirectoryOutside/flutter_test').existsSync(), isTrue);
    });

    test('cloneRepository() over existing dir.', () async {
      await cliCommand.runCliCommand(executable: 'mkdir', arguments: ['$workingDirectoryOutside/flutter_test']);
      final bool isSuccessful = await gitCloneManager.cloneRepository();
      expect(isSuccessful, isTrue);
      expect(Directory('$workingDirectoryOutside/flutter_test').existsSync(), isTrue);
      expect(await gitCli.isGitRepository('$workingDirectoryOutside/flutter_test'), isTrue);
    });

    test('deleteRepository()', () async {
      final bool isSuccessful = await gitCloneManager.cloneRepository();
      expect(isSuccessful, isTrue);
      expect(Directory(targetRepoCheckoutDirectory).existsSync(), isTrue);
      await gitCloneManager.deleteRepository();
      expect(Directory(targetRepoCheckoutDirectory).existsSync(), isFalse);
    });

    test('revertCommit()', () async {

    });

    tearDown(() async {
      await cliCommand.runCliCommand(executable: 'rm', arguments: ['-rf', targetRepoCheckoutDirectory]);
    });
  });
}
