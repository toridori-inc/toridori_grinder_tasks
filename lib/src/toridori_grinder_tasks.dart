import 'dart:io';

import 'package:github/github.dart';
import 'package:grinder/grinder.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

void addAllTasks({
  required String repositoryOwner,
  required String repositoryName,
}) {
  addFormatTask();
  addReleaseTask(
    repositoryOwner: repositoryOwner,
    repositoryName: repositoryName,
  );
  addOnReleasePrMergedTask();
}

void addFormatTask() {
  addTask(
    GrinderTask(
      'format',
      description: 'コードのフォーマット',
      taskFunction: () => _format(),
    ),
  );
}

void addReleaseTask({
  required String repositoryOwner,
  required String repositoryName,
}) {
  addTask(
    GrinderTask(
      'release',
      description:
          'Release時のコマンド--version-name=X.X.Xでバージョン指定\ngrind r --version-name=',
      taskFunction: () async {
        run('git', arguments: ['switch', 'develop']);
        run('git', arguments: ['pull']);
        log('最新のdevブランチに切り替えました');

        final pullRequestTitle = _incrementVersion();
        log('バージョンを更新しました');

        _format();
        log('コードを整形しました');

        run('git', arguments: ['add', '.']);
        run('git', arguments: ['commit', '-m', 'pftest']);
        run('git', arguments: ['push']);
        log('修正をコミットしてpushしました');

        await _createPullRequest(
          title: pullRequestTitle,
          repositoryOwner: repositoryOwner,
          repositoryName: repositoryName,
        );
        log('プルリクを作成しました');
      },
    ),
  );
}

void addOnReleasePrMergedTask() {
  addTask(
    GrinderTask(
      'on-release-pr-merged',
      description: 'Release PRがマージされたときのタスク',
      taskFunction: () async {
        // 環境変数からgitのユーザー名とメールアドレスを取得
        final envVars = Platform.environment;
        final gitUserName = envVars['GIT_USER_NAME'];
        final gitUserEmail = envVars['GIT_USER_EMAIL'];
        run('git',
            arguments: ['config', '--local', 'user.email', '"$gitUserEmail"']);
        run('git',
            arguments: ['config', '--local', 'user.name', '"$gitUserName"']);
        _tag();
        log('tagを打ちました');
        await closeMilestone();
        log('milestoneをcloseしました');
      },
    ),
  );
}

/// バージョン更新
String _incrementVersion() {
  final args = context.invocation.arguments;
  final newVersionName = args.getOption('version-name');
  if (newVersionName == null) {
    fail('--version-name=X.X.Xで新しいバージョン名を指定してください');
  }

  final pubspecFile = File('./pubspec.yaml');
  final pubspecString = pubspecFile.readAsStringSync();

  final pubspec = loadYaml(pubspecString);
  final version = pubspec['version'] as String;
  final splits = version.split('+');
  final versionCode = int.parse(splits[1]);
  final newVersionCode = versionCode + 1;

  final updatedPubspecString = pubspecString.replaceFirst(
    'version: $version',
    'version: $newVersionName+$newVersionCode',
  );
  pubspecFile.writeAsStringSync(updatedPubspecString);

  return '$newVersionName+$newVersionCode';
}

/// PR作成
Future<void> _createPullRequest({
  required String title,
  required String repositoryOwner,
  required String repositoryName,
}) async {
  // ダイアログで認証を求める
  final github = GitHub(auth: findAuthenticationFromEnvironment());
  log('GitHubにログインしました');
  await github.pullRequests.create(
    RepositorySlug(repositoryOwner, repositoryName),
    CreatePullRequest(title, 'develop', 'master'),
  );
}

/// コードのフォーマット
String _format() {
  final result = run(
    '/bin/sh',
    arguments: [
      '-c',
      r'find . -type f \( ! -name "*.freezed.dart" -and ! -name "*.g.dart" -and ! -name "*.graphql.dart" \) -and -name "*.dart" | xargs dart format --fix -l 200',
    ],
    workingDirectory: 'lib',
  );

  return result;
}

// Github Actions側でmasterをチェックアウトする前提
void _tag() {
  final pubspecFile = File('./pubspec.yaml');
  final pubspecString = pubspecFile.readAsStringSync();

  final pubspec = loadYaml(pubspecString);
  final version = pubspec['version'] as String;

  // 現在のバージョンでタグを打つ
  run('git', arguments: ['tag', version]);
  // リモートに反映
  run('git', arguments: ['push', 'origin', version]);
}

// milestoneをcloseする
Future<void> closeMilestone() async {
  final envVars = Platform.environment;
  final githubToken = envVars['GITHUB_TOKEN'];
  final repository = envVars['REPO'];
  final milestoneNumber = envVars['MILESTONE_NUMBER'];
  final result = await http.patch(
    Uri.parse(
        'https://api.github.com/repos/$repository/milestones/$milestoneNumber'),
    headers: {
      'Authorization': 'token $githubToken',
      'Accept': 'application/vnd.github.v3+json',
    },
    body: '{"state":"closed"}',
  );
  log(result.statusCode.toString());
  log(result.body);
}
