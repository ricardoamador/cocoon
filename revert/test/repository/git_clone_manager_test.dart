

import 'dart:io';

import 'package:github/github.dart';
import 'package:revert/cli/cli_command.dart';
import 'package:revert/repository/git_access_method.dart';
import 'package:revert/repository/git_cli.dart';
import 'package:revert/repository/git_clone_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Clone is successful', () {
    
    final String workingDirectory = '${Directory.current.path}/test/repository';
    final String targetRepo = '${Directory.current.path}/test/repository/flutter_test';
    final CliCommand cliCommand = CliCommand();
    final GitCli gitCli = GitCli(GitAccessMethod.SSH, cliCommand);
    final GitCloneManager gitCloneManager = GitCloneManager(gitCli);

    test('Repository is not ready if GitCloneManager did not create it.', () async {
      final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
      await cliCommand.runCliCommand(executable: 'git', arguments: ['init', targetRepo], workingDirectory: workingDirectory);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isFalse);
    });

    test('Repository will get cloned over outside created repository.', () async {
      final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
      await cliCommand.runCliCommand(executable: 'git', arguments: ['init', targetRepo], workingDirectory: workingDirectory);
      await gitCloneManager.cloneRepository(slug, workingDirectory);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isTrue);
    });

    test('Clone repository is successful.', () async {
      final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
      await gitCloneManager.cloneRepository(slug, workingDirectory);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isTrue);
    });

    test('Cloning blocks subsequent clone attempts with same instance, same repo target.', () async {
      final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
      final Future<bool> clone1 = gitCloneManager.cloneRepository(slug, workingDirectory);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isFalse);
      final bool clone2 = await gitCloneManager.cloneRepository(slug, workingDirectory);
      expect(clone2, isTrue);
      await clone1.then((value) => expect(value, isTrue));
      expect(Directory(targetRepo).existsSync(), isTrue);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isTrue);
    });

    test('Cloning blocks subsequent clone attempts with different instance, same repo target.', () async {
      final RepositorySlug slug = RepositorySlug('ricardoamador', 'flutter_test');
      final Future<bool> clone1 = gitCloneManager.cloneRepository(slug, workingDirectory);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isFalse);
      final GitCloneManager gitCloneManager2 = GitCloneManager(gitCli);
      final bool clone2 = await gitCloneManager2.cloneRepository(slug, workingDirectory);
      expect(clone2, isTrue);
      await clone1.then((value) => expect(value, isTrue));
      expect(Directory(targetRepo).existsSync(), isTrue);
      expect(await gitCloneManager.isRepositoryReady(slug, workingDirectory), isTrue);
    });

    tearDown(() async {
      await cliCommand.runCliCommand(executable: 'rm', arguments: ['-rf', targetRepo]);
      await cliCommand.runCliCommand(executable: 'rm', arguments: ['-rf', '$workingDirectory/flutter_test.clone']);
    });
  });  
}