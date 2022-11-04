// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:revert/service/bigquery.dart';
import 'package:revert/service/config.dart';
import 'package:revert/service/github_service.dart';
import 'package:revert/service/secrets.dart';
import 'package:github/github.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:graphql/client.dart';

import 'fake_github_service.dart';

// Represents a fake config to be used in unit test.
class FakeConfig extends Config {
  FakeConfig({
    this.githubClient,
    this.githubGraphQLClient,
    this.githubService,
    this.rollerAccountsValue,
    this.overrideTreeStatusLabelValue,
    this.webhookKey,
    this.kPubsubPullNumberValue,
    this.bigqueryService,
  }) : super(
          cacheProvider: Cache.inMemoryCacheProvider(4),
          secretManager: LocalSecretManager(),
        );

  GitHub? githubClient;
  GraphQLClient? githubGraphQLClient;
  GithubService? githubService = FakeGithubService();
  Set<String>? rollerAccountsValue;
  String? overrideTreeStatusLabelValue;
  String? webhookKey;
  int? kPubsubPullNumberValue;
  BigqueryService? bigqueryService;

  @override
  int get kPubsubPullNumber => kPubsubPullNumberValue ?? 1;

  @override
  Future<GitHub> createGithubClient(RepositorySlug slug) async => githubClient!;

  @override
  Future<GitHub> createFlutterGitHubBotClient(RepositorySlug slug) async => githubClient!;

  @override
  Future<GithubService> createGithubService(RepositorySlug slug) async => githubService ?? FakeGithubService();

  @override
  Future<GraphQLClient> createGitHubGraphQLClient(RepositorySlug slug) async => githubGraphQLClient!;
  @override
  Set<String> get rollerAccounts =>
      rollerAccountsValue ??
      const <String>{
        'skia-flutter-autoroll',
        'engine-flutter-autoroll',
        'dependabot[bot]',
        'dependabot',
      };

  @override
  String get overrideTreeStatusLabel => overrideTreeStatusLabelValue ?? 'warning: land on red to fix tree breakage';

  @override
  Future<String> getWebhookKey() async {
    return webhookKey ?? 'not_a_real_key';
  }

  @override
  Future<String> getFlutterGitHubBotToken() async {
    return 'not_a_real_token';
  }

  @override
  Future<BigqueryService> createBigQueryService() async => bigqueryService!;
}
