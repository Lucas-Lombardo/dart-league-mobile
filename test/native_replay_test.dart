import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fixture in ['frame_copy', 'composition']) {
    test(
      'native replay $fixture with AddressSanitizer',
      () async {
        final temp = await Directory.systemTemp.createTemp('replay-native-');
        try {
          final source = fixture == 'frame_copy'
              ? 'ReplayFrameCopy'
              : 'ReplayComposition';
          final executable = '${temp.path}/test';
          final compile = await Process.run('xcrun', [
            'swiftc',
            '-sanitize=address',
            '-module-cache-path',
            '${temp.path}/modules',
            'ios/Runner/$source.swift',
            'test/native/replay_${fixture}_test.swift',
            '-o',
            executable,
          ]);
          expect(
            compile.exitCode,
            0,
            reason: '${compile.stdout}\n${compile.stderr}',
          );
          final result = await Process.run(executable, []);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        } finally {
          await temp.delete(recursive: true);
        }
      },
      skip: !Platform.isMacOS ? 'CoreVideo/AVFoundation require macOS' : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
