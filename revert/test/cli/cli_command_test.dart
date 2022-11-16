// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:revert/cli/cli_command.dart';
import 'package:test/test.dart';

void main() {
  group('Testing git command locally', () {
    test('Checkout locally.', () async {
      String executable = 'ls';
      if (Platform.isWindows) {
        executable = 'dir';
      }

      final ProcessResult processResult = await CliCommand.runCliCommand(executable: executable, arguments: []);
      expect(processResult.exitCode, isZero);
    });
  });
}
