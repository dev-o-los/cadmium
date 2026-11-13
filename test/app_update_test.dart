import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/providers/update_provider.dart';
import 'package:wavify/widgets/app_update_sheet.dart';

void main() {
  group('AppUpdateInfo Semver & JSON Parsing Tests', () {
    test('Correctly parses release JSON with APK asset', () {
      final json = {
        'tag_name': 'v1.0.5',
        'name': 'Cadmium v1.0.5',
        'body': '• Fixed audio playback\n• Added new UI',
        'html_url': 'https://github.com/dev-o-los/cadmium/releases/tag/v1.0.5',
        'published_at': '2026-11-12T10:00:00Z',
        'assets': [
          {
            'name': 'cadmium-v1.0.5.apk',
            'size': 63786869,
            'browser_download_url':
                'https://github.com/dev-o-los/cadmium/releases/download/v1.0.5/cadmium-v1.0.5.apk',
          },
          {
            'name': 'source.zip',
            'size': 1024,
            'browser_download_url': 'https://github.com/...',
          }
        ],
      };

      final info = AppUpdateInfo.fromJson(json);

      expect(info.tagName, 'v1.0.5');
      expect(info.version, '1.0.5');
      expect(info.releaseName, 'Cadmium v1.0.5');
      expect(info.releaseNotes, contains('Fixed audio playback'));
      expect(info.apkFileName, 'cadmium-v1.0.5.apk');
      expect(info.apkDownloadUrl, contains('.apk'));
      expect(info.apkSizeBytes, 63786869);
      expect(info.formattedSize, '60.8 MB');
      expect(info.formattedDate, contains('2026'));
    });

    test('isNewerThan correctly detects newer semver versions', () {
      const releaseInfo = AppUpdateInfo(
        tagName: 'v1.0.5',
        version: '1.0.5',
        releaseName: 'v1.0.5',
        releaseNotes: 'notes',
        htmlUrl: 'https://...',
      );

      // Newer than older patch
      expect(releaseInfo.isNewerThan('1.0.4'), isTrue);
      expect(releaseInfo.isNewerThan('1.0.4+5'), isTrue);
      expect(releaseInfo.isNewerThan('v1.0.4'), isTrue);

      // Same version is not newer
      expect(releaseInfo.isNewerThan('1.0.5'), isFalse);
      expect(releaseInfo.isNewerThan('v1.0.5+1'), isFalse);

      // Older than future version
      expect(releaseInfo.isNewerThan('1.0.6'), isFalse);
      expect(releaseInfo.isNewerThan('1.1.0'), isFalse);
      expect(releaseInfo.isNewerThan('2.0.0'), isFalse);
    });

    test('compareSemver handles various formats', () {
      expect(AppUpdateInfo.compareSemver('1.1.0', '1.0.9'), greaterThan(0));
      expect(AppUpdateInfo.compareSemver('2.0.0', '1.9.9'), greaterThan(0));
      expect(AppUpdateInfo.compareSemver('1.0.4', '1.0.4'), equals(0));
      expect(AppUpdateInfo.compareSemver('1.0.4+5', '1.0.4+2'), equals(0));
      expect(AppUpdateInfo.compareSemver('1.0.4', '1.0.5'), lessThan(0));
    });
  });

  group('AppUpdateSheetContent Widget Tests', () {
    testWidgets('Renders update available sheet content correctly', (tester) async {
      const updateInfo = AppUpdateInfo(
        tagName: 'v1.0.5',
        version: '1.0.5',
        releaseName: 'Cadmium v1.0.5',
        releaseNotes: 'Exciting new features and fixes',
        apkDownloadUrl: 'https://github.com/cadmium.apk',
        apkFileName: 'cadmium.apk',
        apkSizeBytes: 52428800, // 50 MB
        htmlUrl: 'https://github.com/dev-o-los/cadmium',
      );

      final state = const AppUpdateState(
        status: UpdateStatus.updateAvailable,
        updateInfo: updateInfo,
        currentVersion: '1.0.4',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateProvider.overrideWith((ref) => MockUpdateNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AppUpdateSheetContent(),
            ),
          ),
        ),
      );

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('v1.0.5'), findsOneWidget);
      expect(find.text("WHAT'S NEW"), findsOneWidget);
      expect(find.text('Exciting new features and fixes'), findsOneWidget);
      expect(find.text('Download & Install'), findsOneWidget);
      expect(find.text('View on GitHub'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('Renders downloading state with progress bar', (tester) async {
      const updateInfo = AppUpdateInfo(
        tagName: 'v1.0.5',
        version: '1.0.5',
        releaseName: 'Cadmium v1.0.5',
        releaseNotes: 'Notes',
        apkDownloadUrl: 'https://github.com/cadmium.apk',
        apkFileName: 'cadmium.apk',
        apkSizeBytes: 104857600,
        htmlUrl: 'https://github.com/dev-o-los/cadmium',
      );

      final state = const AppUpdateState(
        status: UpdateStatus.downloading,
        updateInfo: updateInfo,
        progress: 0.5,
        receivedBytes: 52428800,
        totalBytes: 104857600,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateProvider.overrideWith((ref) => MockUpdateNotifier(state)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AppUpdateSheetContent(),
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}

class MockUpdateNotifier extends UpdateNotifier {
  final AppUpdateState _initial;

  MockUpdateNotifier(this._initial) {
    state = _initial;
  }
}
