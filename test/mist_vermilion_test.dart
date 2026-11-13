import 'dart:io';
import 'dart:ui' as ui;

import 'package:anker_recorder/ai/stt_types.dart';
import 'package:anker_recorder/protocol/models.dart';
import 'package:anker_recorder/state/recorder_controller.dart';
import 'package:anker_recorder/theme/app_theme.dart';
import 'package:anker_recorder/ui/screens/communication_screen.dart';
import 'package:anker_recorder/ui/screens/recording_detail_screen.dart';
import 'package:anker_recorder/ui/shell.dart';
import 'package:anker_recorder/ui/widgets/scan_sheet.dart';
import 'package:anker_recorder/ui/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Optional PNG export uses the exact production widgets and native Mac fonts.
// flutter test test/mist_vermilion_test.dart --dart-define=FLUTTER_SCREENSHOT_DIR=design/mist-vermilion-flutter-screenshots
void main() {
  const output = String.fromEnvironment('FLUTTER_SCREENSHOT_DIR');
  setUpAll(() async {
    if (output.isEmpty) return;
    for (final font in [
      ('PingFang SC', '/System/Library/Fonts/STHeiti Light.ttc'),
      ('Ahem', '/System/Library/Fonts/STHeiti Light.ttc'),
      (
        'Songti SC',
        const String.fromEnvironment(
          'SCREENSHOT_SERIF_FONT',
          defaultValue: '/System/Library/Fonts/Supplemental/Songti.ttc',
        ),
      ),
      ('Baskerville', '/System/Library/Fonts/Supplemental/Georgia.ttf'),
    ]) {
      final loader = FontLoader(font.$1);
      loader.addFont(File(font.$2).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('Vermilion palette and Mist typography are shared across the app', () {
    expect(AppColors.bg, const Color(0xfff4f0e6));
    expect(AppColors.accent, const Color(0xffc64129));
    expect(AppColors.textPrimary, const Color(0xff292a23));
    expect(AppColors.talkB, const Color(0xffe6e3d6));
    expect(AppTheme.light.appBarTheme.titleTextStyle?.fontFamily, 'Songti SC');
    expect(AppTheme.light.colorScheme.onPrimary, AppColors.onAccent);
    expect(AppTheme.light.colorScheme.secondaryContainer, AppColors.navigation);
    expect(AppTheme.light.colorScheme.surfaceContainerHighest, AppColors.talkB);
  });

  testWidgets('six production surfaces render and preserve navigation', (
    tester,
  ) async {
    final originalShadows = debugDisableShadows;
    if (output.isNotEmpty) debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = originalShadows);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _PreviewController();
    addTearDown(c.dispose);
    final boundary = GlobalKey();

    Future<void> mount(Widget child) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ChangeNotifierProvider<RecorderController>.value(
          value: c,
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 44, bottom: 24),
                  viewPadding: const EdgeInsets.only(top: 44, bottom: 24),
                ),
                child: child!,
              ),
            ),
            home: child,
          ),
        ),
      );
      if (output.isNotEmpty) {
        await tester.runAsync(() async {
          for (final asset in [
            'd3200_device_white.webp',
            'd3200_device_connected_white.webp',
            'd3200_chargebox_white.webp',
            'white_03_device_connect.webp',
            'guide_connect_case.webp',
          ]) {
            await precacheImage(
              AssetImage('assets/product/$asset'),
              boundary.currentContext!,
            );
          }
        });
      }
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      if (output.isEmpty) return;
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File(
          '$output/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await mount(const AppShell());
    expect(find.byType(Pebbles), findsOneWidget);
    c.showPlaybackPreview();
    await tester.pumpAndSettle();
    await capture('recordings');
    await tester.tap(
      find.byKey(ValueKey('recording-row-${c.exportedPaths.first}')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RecordingDetailScreen), findsOneWidget);
    await capture('transcript');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-device')));
    await tester.pumpAndSettle();
    expect(find.byType(ProductStage), findsOneWidget);
    await capture('device');
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('原文语言'), findsOneWidget);
    await capture('settings');

    c.disconnectPreview();
    c.devices.add(
      ScannedDevice(
        id: 'preview',
        name: 'soundcore Work',
        rssi: -42,
        isD3200: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nav-device')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫描设备'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanDevicesSheet), findsOneWidget);
    await capture('scan');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    c.recording = true;
    await mount(const CommunicationScreen());
    expect(
      tester
          .widget<RotatedBox>(
            find.byKey(const ValueKey('communication-guest-rotation')),
          )
          .quarterTurns,
      2,
    );
    await capture('communication');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = originalShadows;
  });
}

class _PreviewController extends RecorderController {
  _PreviewController() : super(loadPersistedState: false) {
    connected = true;
    activeDevice = ScannedDevice(
      id: 'preview',
      name: 'soundcore Work',
      rssi: -42,
      isD3200: true,
    );
    autoTranscribe = true;
    transcriptLanguage = 'zh';
    ownerLanguage = 'zh';
    guestLanguage = 'en';
    info = DeviceInfoModel(
      battery: 86,
      boxBattery: 72,
      firmwareVersion: '1.0.8',
      serialNumber: 'D3200',
    );
    exportedPaths.addAll([
      '/tmp/1794528000_产品讨论.wav',
      '/tmp/1794441600_周末访谈.wav',
      '/tmp/1794355200_旅途随记.wav',
    ]);
    playingPath = exportedPaths.first;
    duration = const Duration(minutes: 24, seconds: 18);
    position = const Duration(minutes: 8, seconds: 42);
    ownerTranslationTurns = const [
      SttTranslationTurn(
        targetLanguage: 'zh',
        sourceLanguage: 'en',
        text: '我们可以沿着河边走。',
        isFinal: true,
      ),
      SttTranslationTurn(
        targetLanguage: 'zh',
        sourceLanguage: 'en',
        text: '前面的咖啡馆有一个安静的露台。',
        isFinal: true,
      ),
    ];
    guestTranslationTurns = const [
      SttTranslationTurn(
        targetLanguage: 'en',
        sourceLanguage: 'zh',
        text: 'That sounds lovely.',
        isFinal: true,
      ),
      SttTranslationTurn(
        targetLanguage: 'en',
        sourceLanguage: 'zh',
        text: 'Let’s stop there and enjoy the afternoon.',
        isFinal: true,
      ),
    ];
  }

  @override
  RecordingViewData recordingView(RecordingReference reference) {
    final path = reference.path ?? exportedPaths.first;
    final index = exportedPaths.indexOf(path);
    return RecordingViewData(
      reference: reference,
      path: path,
      title: ['产品讨论', '周末访谈', '旅途随记'][index < 0 ? 0 : index],
      text:
          '说话人 1：我们希望录音结束后，可以安静地回顾完整的对话。\n说话人 2：先保留最自然的表达，再把重要的细节慢慢整理出来。\n说话人 1：下次见面时，带上这些记录继续讨论。',
      sourceLanguage: 'zh',
      translation: const RecordingTranslation(
        text:
            'We want to revisit the conversation after recording.\nKeep the natural expression and organize the details.',
        sourceLanguage: 'zh',
        targetLanguage: 'en',
        provider: SttProvider.soniox,
        sourceRevision: 1,
      ),
    );
  }

  @override
  Future<void> refreshFilesOnTabEnter() async {}
  @override
  Future<void> refreshInfoOnDeviceTabEnter() async {}
  void showPlaybackPreview() {
    playingPath = exportedPaths.first;
    duration = const Duration(minutes: 24, seconds: 18);
    position = const Duration(minutes: 8, seconds: 42);
    notifyListeners();
  }

  void disconnectPreview() {
    connected = false;
    activeDevice = null;
    notifyListeners();
  }

  @override
  Future<void> startScan() async {}
}
