// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Wrapper class to create a revert branch that is comprised of the prefix
/// revert_ and the commit sha so the branch is easily identifiable.
class RevertBranchNameFormat {
  final String commitSha;

  const RevertBranchNameFormat(this.commitSha);

  static const String branchPrefix = 'revert';

  String get branch => '${branchPrefix}_$commitSha';
}
