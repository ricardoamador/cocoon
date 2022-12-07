import 'package:revert/model/auto_submit_query_result.dart';

import 'package:github/github.dart' as gh;
import 'validation.dart';

class RevertValidator extends Validation {
  RevertValidator({
    required super.config,
  });

  @override
  Future<ValidationResult> validate(QueryResult result, gh.PullRequest messagePullRequest) {
    throw UnimplementedError();
  }

  // perform a diff to see if the revert is even needed in the first place.
  // when attempting to revert mulitple times github knew the changes were the same
}
