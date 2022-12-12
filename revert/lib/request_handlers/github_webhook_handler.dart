// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:github/github.dart';
import 'package:shelf/shelf.dart';
import 'package:crypto/crypto.dart';

import '../request_handling/pubsub.dart';
import '../service/config.dart';
import '../service/log.dart';
import '../server/request_handler.dart';
import 'handler_exceptions.dart';

/// Handler for processing GitHub webhooks.
///
/// On events where an 'autosubmit' label was added to a pull request,
/// check if the pull request is mergable and publish to pubsub.
class GithubWebhookHandler extends RequestHandler {
  const GithubWebhookHandler({
    required super.config,
    this.pubsub = const PubSub(),
  });

  final PubSub pubsub;

  @override
  Future<Response> post(Request request) async {
    final Map<String, String> reqHeader = request.headers;
    log.info('Header: $reqHeader');

    final String? gitHubEvent = request.headers['X-GitHub-Event'];

    if (gitHubEvent == null || request.headers['X-Hub-Signature'] == null) {
      throw const BadRequestException('Missing required headers.');
    }
    final List<int> requestBytes = await request.read().expand((_) => _).toList();
    final String? hmacSignature = request.headers['X-Hub-Signature'];
    //TODO disable security to see if we can bypass for testing purposes.
    // if (!await _validateRequest(hmacSignature, requestBytes)) {
    //   throw const Forbidden();
    // }

    bool hasRevertLabel = false;
    final String rawBody = utf8.decode(requestBytes);
    log.info('Recieved rawBody $rawBody from webhook.');
    final body = json.decode(rawBody) as Map<String, dynamic>;

    log.info('Decoded body $body from raw data from webhook.');

    // TODO state must also be closed and merged as well as having the correct label.
    if (!body.containsKey('pull_request') || !((body['pull_request'] as Map<String, dynamic>).containsKey('labels'))) {
      return Response.ok(jsonEncode(<String, String>{}));
    }

    final PullRequest pullRequest = PullRequest.fromJson(body['pull_request'] as Map<String, dynamic>);
    hasRevertLabel = pullRequest.labels!.any((label) => label.name == Config.kRevertLabel);

    if (hasRevertLabel) {
      log.info('Found pull request with revert label.');
      await pubsub.publish('revert-queue', pullRequest);
    }

    return Response.ok(rawBody);
  }

  Future<bool> _validateRequest(
    String? signature,
    List<int> requestBody,
  ) async {
    final String rawKey = await config.getWebhookKey();
    final List<int> key = utf8.encode(rawKey);
    final Hmac hmac = Hmac(sha1, key);
    final Digest digest = hmac.convert(requestBody);
    final String bodySignature = 'sha1=$digest';
    return bodySignature == signature;
  }
}
