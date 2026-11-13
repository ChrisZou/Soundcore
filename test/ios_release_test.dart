import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('scripts/upload-testflight.sh').readAsStringSync();
  final project = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  test(
    'all iOS targets use company automatic signing and required privacy keys',
    () {
      for (final entry in {
        'DEVELOPMENT_TEAM': {'W4SX57U6XB'},
        'CODE_SIGN_STYLE': {'Automatic'},
        'PRODUCT_BUNDLE_IDENTIFIER': {
          'com.weallwitness.soundcore',
          'com.weallwitness.soundcore.RunnerTests',
        },
      }.entries) {
        final values = RegExp(
          '${entry.key} = ([^;]+);',
        ).allMatches(project).map((m) => m[1]!).toList();
        expect(values, hasLength(6));
        expect(values.toSet(), entry.value);
      }
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      for (final key in [
        'NSMicrophoneUsageDescription',
        'NSBluetoothAlwaysUsageDescription',
        'NSBluetoothPeripheralUsageDescription',
        'NSLocalNetworkUsageDescription',
        'NSLocationWhenInUseUsageDescription',
      ]) {
        expect(plist, contains('<key>$key</key>'));
      }
      expect(
        plist,
        matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
      );
      expect(plist, contains('<string>soundcore</string>'));
      expect(
        File('scripts/install-ios.sh').readAsStringSync(),
        contains('TEAM_ID="W4SX57U6XB"'),
      );
    },
  );

  test(
    'release script fails cleanly and reserves increasing builds across retries',
    () async {
      final dir = await Directory.systemTemp.createTemp('soundcore-release-');
      addTearDown(() => dir.delete(recursive: true));
      for (final folder in ['scripts', 'bin', 'ios/Runner.xcodeproj']) {
        await Directory('${dir.path}/$folder').create(recursive: true);
      }
      // Replace only the key location in this disposable copy. No real key or
      // Apple service is used; flutter/xcrun are test doubles on a private PATH.
      final keyLine =
          r'KEY_PATH="${HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"';
      expect(script, contains(keyLine));
      final copy = File('${dir.path}/scripts/upload-testflight.sh');
      await copy.writeAsString(
        script.replaceFirst(keyLine, 'KEY_PATH="${dir.path}/fixture.p8"'),
      );
      await File(
        '${dir.path}/ios/Runner.xcodeproj/project.pbxproj',
      ).writeAsString(project);
      final pubspec = File('${dir.path}/pubspec.yaml');
      await pubspec.writeAsString('name: fixture\nversion: 1.2.3+1\n');
      await File('${dir.path}/bin/flutter').writeAsString(
        r'''#!/usr/bin/env bash
set -euo pipefail
printf 'flutter %s\n' "$*" >> calls.log
if [[ "$1" == test && "${FAKE_TEST_EXIT:-0}" != 0 ]]; then exit "$FAKE_TEST_EXIT"; fi
if [[ "$1" == build ]]; then
  if [[ "${FAKE_BUILD_EXIT:-0}" != 0 ]]; then exit "$FAKE_BUILD_EXIT"; fi
  mkdir -p build/ios/ipa
  printf 'new IPA' > build/ios/ipa/fixture.ipa
fi
''',
      );
      await File('${dir.path}/bin/xcrun').writeAsString(r'''#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >> calls.log
exit "${FAKE_UPLOAD_EXIT:-0}"
''');
      for (final binary in ['flutter', 'xcrun']) {
        await Process.run('chmod', ['+x', '${dir.path}/bin/$binary']);
      }
      Future<ProcessResult> run([Map<String, String> extra = const {}]) =>
          Process.run(
            'bash',
            [copy.path],
            workingDirectory: Directory.systemTemp.path,
            environment: {
              'PATH': '${dir.path}/bin:${Platform.environment['PATH']}',
              ...extra,
            },
          );
      int build() => int.parse(
        RegExp(
          r'version: 1\.2\.3\+(\d+)',
        ).firstMatch(pubspec.readAsStringSync())![1]!,
      );
      final missing = await run();
      expect(missing.exitCode, isNot(0));
      expect(missing.stderr, contains('key missing or unreadable'));
      expect(build(), 1);
      expect(File('${dir.path}/calls.log').existsSync(), isFalse);
      await File(
        '${dir.path}/fixture.p8',
      ).writeAsString('test placeholder, not a private key');

      final first = await run();
      expect(first.exitCode, 0, reason: '${first.stderr}');
      final firstBuild = build();
      expect(firstBuild, greaterThanOrEqualTo(2026111301));
      final calls = File('${dir.path}/calls.log');
      expect(
        calls.readAsStringSync(),
        contains(
          'flutter test\nflutter analyze\nflutter build ipa --release --export-method app-store',
        ),
      );
      expect(
        calls.readAsStringSync(),
        contains(
          '--apiKey Q4F3H4FLRZ --apiIssuer 69a6de91-4f5b-47e3-e053-5b8c7c11a4d1',
        ),
      );
      expect(first.stdout, contains('altool upload succeeded'));

      final second = await run({'FAKE_UPLOAD_EXIT': '9'});
      expect(second.exitCode, 9);
      expect(build(), firstBuild + 1);
      expect(second.stderr, contains('altool upload failed'));
      expect(
        Directory(
          '${dir.path}/build/ios',
        ).listSync().where((f) => f.path.contains('previous-ipa.')),
        isNotEmpty,
      );

      await calls.writeAsString('');
      final failure = await run({'FAKE_BUILD_EXIT': '7'});
      expect(failure.exitCode, 7);
      expect(build(), firstBuild + 2);
      expect(calls.readAsStringSync(), isNot(contains('xcrun')));
      expect(Directory('${dir.path}/build/ios/ipa').existsSync(), isFalse);

      await calls.writeAsString('');
      final failedTests = await run({'FAKE_TEST_EXIT': '5'});
      expect(failedTests.exitCode, 5);
      expect(calls.readAsStringSync(), 'flutter test\n');
      expect(
        Directory('${dir.path}/.dart_tool/upload-testflight.lock').existsSync(),
        isFalse,
      );

      await pubspec.writeAsString('version: 1.2.3+9999999999\n');
      expect((await run()).exitCode, 0);
      expect(build(), 10000000000);
    },
  );
}
