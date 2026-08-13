import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host side of the demo run. Its only job is to catch the beat marks the flow
/// reports and drop them where `tool/demo/edit.ps1` looks for them.
Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 15),
      responseDataCallback: (data) async {
        final marks = data?['marks'];
        if (marks == null) {
          stderr.writeln('demo_driver: the flow reported no beat marks.');
          exitCode = 1;
          return;
        }

        final out = File('build/demo/marks.json');
        await out.parent.create(recursive: true);
        await out.writeAsString(
          const JsonEncoder.withIndent('  ').convert(marks),
        );
        stdout.writeln('demo_driver: wrote ${out.path}');
      },
    );
