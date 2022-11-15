// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Simple wrapper class to send a different command than the default command to 
/// some of the GitManager methods.
class CommandStrategy {
  late List<String> commandList;

  CommandStrategy(List<String>? commandList) {
    commandList ??= [];
  }

  void addCommand(String command) {
    commandList.add(command);
  }

  List<String> get getCommandList => commandList;
}
