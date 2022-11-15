import 'dart:io';

import 'package:revert/cli/cli_command.dart';
import 'package:test/test.dart';

void main() {
  group('Testing git command locally', () {
    test('Checkout locally.', () async {
      final String workingDirectory = '${Directory.current.path}/test/repository/flutter_test';
      // final ProcessResult processResult = await CliCommand.runCliCommand(executable: 'git', arguments: ['clone', 'git@github.com:ricardoamador/flutter_test.git'], throwOnError: true, workingDirectory: workingDirectory,);
      // print(processResult.exitCode);
      print(workingDirectory);
      final ProcessResult processResult2 = await CliCommand.runCliCommand(
        executable: 'git',
        arguments: ['branch'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      print(processResult2.stdout);

      // final ProcessResult processResult3 = await CliCommand.runCliCommand(executable: 'git', arguments: ['branch', 'new_branch'], throwOnError: true, workingDirectory: workingDirectory,);

      final ProcessResult processResult4 = await CliCommand.runCliCommand(
          executable: 'git', arguments: ['pull', '--rebase'], throwOnError: true, workingDirectory: workingDirectory);
      print(processResult4.stdout);

      final ProcessResult processResult5 =
          await CliCommand.runCliCommand(executable: 'git', arguments: ['branch'], workingDirectory: workingDirectory);
      expect((processResult5.stdout as String).contains('new_branch'), isTrue);
    });
  });
}
