import 'package:grinder/grinder.dart';

void addAllTasks() {
  addFormatTask();
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
