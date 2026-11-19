import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:anker_recorder/ai/agent_plan_asr.dart';
import 'package:anker_recorder/ai/agent_plan_protocol.dart';
import 'package:anker_recorder/ai/agent_plan_transport.dart';
import 'package:anker_recorder/ai/stt_types.dart';
import 'package:anker_recorder/audio/recording_pcm.dart';
import 'package:anker_recorder/state/agent_plan_key_store.dart';
import 'package:anker_recorder/state/app_settings_store.dart';
import 'package:anker_recorder/state/recorder_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _response(
  Map<String, Object?> payload, {
  int flags = 1,
  bool empty = false,
}) {
  final body = empty ? <int>[] : gzip.encode(utf8.encode(jsonEncode(payload)));
  final sizeOffset = flags & 1 == 0 ? 4 : 8;
  final bytes = Uint8List(sizeOffset + 4 + body.length)
    ..setAll(0, [0x11, 0x90 | flags, 0x11, 0])
    ..setAll(sizeOffset + 4, body);
  final data = ByteData.sublistView(bytes);
  if (flags & 1 != 0) data.setInt32(4, flags & 2 == 0 ? 1 : -3);
  data.setUint32(sizeOffset, body.length);
  return bytes;
}

Uint8List _wave({int rate = 48000, int channels = 2, int samples = 9603}) {
  final block = channels * 2;
  final size = samples * block;
  final bytes = Uint8List(54 + size);
  // An odd-sized padded chunk before fmt tests RIFF chunk traversal.
  for (final entry in {
    0: 'RIFF',
    8: 'WAVE',
    12: 'JUNK',
    22: 'fmt ',
    46: 'data',
  }.entries) {
    bytes.setAll(entry.key, ascii.encode(entry.value));
  }
  final data = ByteData.sublistView(bytes)
    ..setUint32(4, bytes.length - 8, Endian.little)
    ..setUint32(16, 1, Endian.little)
    ..setUint32(26, 16, Endian.little)
    ..setUint16(30, 1, Endian.little)
    ..setUint16(32, channels, Endian.little)
    ..setUint32(34, rate, Endian.little)
    ..setUint32(38, rate * block, Endian.little)
    ..setUint16(42, block, Endian.little)
    ..setUint16(44, 16, Endian.little)
    ..setUint32(50, size, Endian.little);
  for (var i = 0; i < samples * channels; i++) {
    data.setInt16(54 + i * 2, i % channels == 0 ? -1000 : 2000, Endian.little);
  }
  return bytes;
}

class _Transport implements AgentPlanTransport {
  final responses = StreamController<dynamic>();
  final sent = <Uint8List>[];
  final configured = Completer<void>();
  final lastAudio = Completer<void>();
  int connections = 0;
  bool closed = false;
  @override
  Future<Stream<dynamic>> connect(String key) async {
    connections++;
    return responses.stream;
  }

  @override
  void send(Uint8List frame) {
    sent.add(frame);
    if (frame[1] == 0x11) configured.complete();
    if (frame[1] == 0x23) lastAudio.complete();
  }

  @override
  void close({bool abort = false}) {
    closed = true;
    unawaited(responses.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File file;
  late _Transport transport;
  late AgentPlanAsr service;
  // Generated marker solely for exercising secret handling in memory.
  String sentinel() => 'mock-${identityHashCode(Object())}';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plan-asr-');
    file = await File('${dir.path}/990.wav').writeAsBytes(_wave());
    transport = _Transport();
    service = AgentPlanAsr(
      transport: () => transport,
      packetInterval: Duration.zero,
    );
  });
  tearDown(() async {
    service.cancel();
    await dir.delete(recursive: true);
  });

  test('Plan-only endpoint, resource, gzip JSON config and PCM contract', () {
    expect(
      AgentPlanProtocol.endpoint,
      'wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_nostream',
    );
    expect(AgentPlanProtocol.resourceId, 'volc.seedasr.sauc.duration');
    final bytes = AgentPlanProtocol.config();
    expect(bytes.take(4), [0x11, 0x11, 0x11, 0]);
    final header = ByteData.sublistView(bytes);
    expect(header.getInt32(4), 1);
    expect(header.getUint32(8), bytes.length - 12);
    final config = jsonDecode(utf8.decode(gzip.decode(bytes.sublist(12))));
    expect(config['audio'], {
      'format': 'pcm',
      'codec': 'raw',
      'rate': 16000,
      'bits': 16,
      'channel': 1,
    });
    expect(config['request']['model_name'], 'bigmodel');
    expect(config['request']['enable_nonstream'], false);
    expect(config['request']['result_type'], 'full');
    expect(config['request']['show_utterances'], true);
  });

  test(
    'streams converted stereo WAV after ack and waits for final result',
    () async {
      final progress = <SttFileProgress>[];
      final work = service.transcribePath(
        file.path,
        apiKey: sentinel(),
        onProgress: progress.add,
      );
      await transport.configured.future;
      expect(transport.sent, hasLength(1));
      transport.responses.add(_response({}));
      await transport.lastAudio.future;
      expect(transport.closed, isFalse);
      expect(transport.sent.map((frame) => frame[1]), [0x11, 0x21, 0x23]);
      expect(
        transport.sent.map((frame) => ByteData.sublistView(frame).getInt32(4)),
        [1, 2, -3],
      );
      final packets = transport.sent.skip(1).map((frame) {
        expect(ByteData.sublistView(frame).getUint32(8), frame.length - 12);
        return Uint8List.fromList(gzip.decode(frame.sublist(12)));
      }).toList();
      expect(packets.map((p) => p.length), [6400, 2]);
      expect(
        ByteData.sublistView(packets.first).getInt16(0, Endian.little),
        500,
      );
      expect(progress.last.stage, SttFileStage.processing);
      expect(progress[1].fraction, 1);
      transport.responses.add(
        _response({
          'result': {'text': '旧草稿'},
        }),
      );
      transport.responses.add(
        _response({
          'result': {'text': '定稿。'},
          'audio_info': {'duration': 201},
        }, flags: 3),
      );
      final result = await work;
      expect(result.text, '定稿。');
      expect(result.durationSec, .201);
      expect(transport.closed, isTrue);
    },
  );

  test(
    'full snapshots replace drafts and retain definite text across empty final flag',
    () {
      final transcript = AgentPlanTranscript();
      void snapshot(String tail, bool definite) {
        transcript.update({
          'result': [
            {
              'utterances': [
                {'text': '第一句。', 'definite': true},
                {'text': tail, 'definite': definite},
              ],
            },
          ],
        }, last: false);
      }

      snapshot('草稿', false);
      expect(transcript.text, '第一句。');
      snapshot('第二句。', true);
      snapshot('第二句。', true);
      final end = AgentPlanProtocol.decode(
        _response({}, flags: 2, empty: true),
      );
      transcript.update(end.payload, last: end.last);
      expect(end.last, isTrue);
      expect(transcript.text, '第一句。第二句。');
    },
  );

  test(
    'device Opus decodes fixed slices or reports a missing native decoder',
    () async {
      // Two synthetic 20 ms Opus silence packets in the recorder framing.
      final raw = Uint8List(163)
        ..setAll(0, [0xf8, 0xff, 0xfe])
        ..setAll(160, [0xf8, 0xff, 0xfe]);
      final path = (await File('${dir.path}/990.opus').writeAsBytes(raw)).path;
      // flutter_tester does not link native plugins. A host build can also
      // exercise the real codec by loading the project's libopus explicitly.
      const library = String.fromEnvironment('SOUNDCORE_TEST_OPUS_LIBRARY');
      if (library.isNotEmpty) DynamicLibrary.open(library);
      if (library.isEmpty &&
          !DynamicLibrary.process().providesSymbol('opus_decoder_create')) {
        await expectLater(
          recordingPcm(path).toList(),
          throwsA(
            isA<RecordingAudioException>().having(
              (e) => e.message,
              'message',
              '无法解码设备 Opus 录音',
            ),
          ),
        );
        return;
      }
      final packets = await recordingPcm(path).toList();
      expect(packets.single.pcm.length, 2 * 320 * 2);
      expect(packets.single.consumed, raw.length);
    },
  );

  test('a final utterance-only snapshot is retained', () {
    final transcript = AgentPlanTranscript()
      ..update({
        'result': {
          'utterances': [
            {'text': '完成'},
          ],
        },
      }, last: true);
    expect(transcript.text, '完成');
  });

  test('rejects malformed framing, gzip and text messages', () {
    for (final invalid in [
      'text',
      <int>[0x11],
      _response({})..[0] = 0x21,
      _response({})..[1] = 0x21,
      _response({})..[2] = 0x12,
      _response({})..[11] = 0,
      _response({})..[12] = 0,
    ]) {
      expect(
        () => AgentPlanProtocol.decode(invalid),
        throwsA(AgentPlanError.protocol),
      );
    }
  });

  test(
    'server errors use documented streaming codes and omit raw error text',
    () {
      final marker = sentinel();
      for (final entry in {
        45000001: AgentPlanError.protocol,
        45000151: AgentPlanError.audio,
        45000081: AgentPlanError.timeout,
        55000031: AgentPlanError.service,
      }.entries) {
        final body = utf8.encode(marker);
        final frame = Uint8List(12 + body.length)
          ..setAll(0, [0x11, 0xf0, 0, 0])
          ..setAll(12, body);
        ByteData.sublistView(frame)
          ..setUint32(4, entry.key)
          ..setUint32(8, body.length);
        expect(() => AgentPlanProtocol.decode(frame), throwsA(entry.value));
        expect(entry.value.toString().contains(marker), isFalse);
      }
      expect(AgentPlanError.handshake(401), AgentPlanError.credentials);
      expect(AgentPlanError.handshake(403), AgentPlanError.credentials);
      expect(AgentPlanError.handshake(429), AgentPlanError.limit);
      expect(AgentPlanError.handshake(503), AgentPlanError.service);
    },
  );

  test(
    'a missing credential or unsupported audio never opens transport',
    () async {
      await expectLater(
        service.transcribePath(file.path, apiKey: null),
        throwsA(AgentPlanError.credentials),
      );
      await file.writeAsBytes(_wave(rate: 44100));
      await expectLater(
        service.transcribePath(file.path, apiKey: sentinel()),
        throwsA(isA<RecordingAudioException>()),
      );
      final encrypted = await File(
        '${dir.path}/990.opus.bin',
      ).writeAsBytes([1, 2, 3]);
      await expectLater(
        service.transcribePath(encrypted.path, apiKey: sentinel()),
        throwsA(isA<RecordingAudioException>()),
      );
      expect(transport.connections, 0);
    },
  );

  test(
    'cancelling during handshake ack closes session before sending audio',
    () async {
      final work = service.transcribePath(file.path, apiKey: sentinel());
      await transport.configured.future;
      service.cancel();
      await expectLater(work, throwsA(AgentPlanError.cancelled));
      expect(transport.sent, hasLength(1));
      expect(transport.closed, isTrue);
    },
  );

  test('cancellation during upload stops subsequent packets', () async {
    final work = service.transcribePath(
      file.path,
      apiKey: sentinel(),
      onProgress: (_) => service.cancel(),
    );
    await transport.configured.future;
    transport.responses.add(_response({}));
    await expectLater(work, throwsA(AgentPlanError.cancelled));
    await Future<void>.delayed(Duration.zero);
    expect(transport.sent, hasLength(2));
  });

  for (final duringAck in [true, false]) {
    test(
      'timeout waiting for ${duringAck ? 'initial ack' : 'final response'} closes transport',
      () async {
        service = AgentPlanAsr(
          transport: () => transport,
          packetInterval: Duration.zero,
          responseTimeout: const Duration(milliseconds: 250),
        );
        final work = service.transcribePath(file.path, apiKey: sentinel());
        await transport.configured.future;
        if (!duringAck) {
          transport.responses.add(_response({}));
          await transport.lastAudio.future;
        }
        await expectLater(work, throwsA(AgentPlanError.timeout));
        expect(transport.closed, isTrue);
      },
    );
  }

  test('remote failure cannot leak a reflected credential', () async {
    final marker = sentinel();
    final work = service.transcribePath(file.path, apiKey: marker);
    await transport.configured.future;
    transport.responses.addError(StateError(marker));
    await expectLater(work, throwsA(AgentPlanError.network));
    expect(AgentPlanError.network.toString().contains(marker), isFalse);
  });

  test(
    'premature final and disconnected stream cannot commit a transcript',
    () async {
      final work = service.transcribePath(file.path, apiKey: sentinel());
      await transport.configured.future;
      transport.responses.add(
        _response({
          'result': {'text': 'incomplete'},
        }, flags: 2),
      );
      await expectLater(work, throwsA(AgentPlanError.protocol));
      transport = _Transport();
      final retry = service.transcribePath(file.path, apiKey: sentinel());
      await transport.configured.future;
      unawaited(transport.responses.close());
      await expectLater(retry, throwsA(AgentPlanError.network));
    },
  );

  test(
    'secure credential save, replacement and clear leave settings JSON secret-free',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = AgentPlanKeyStore();
      final marker = sentinel();
      await store.save(marker);
      expect(await store.read() == marker, isTrue);
      final replacement = sentinel();
      await store.save(replacement);
      expect(await store.read() == replacement, isTrue);
      final settings = AppSettings.fromJson({
        'speechProvider': 'agentPlan',
        'agentPlanKey': replacement,
      });
      final encoded = jsonEncode(settings.toJson());
      expect(encoded.contains(replacement), isFalse);
      expect(settings.speechProvider, SttProvider.agentPlan);
      await store.save(null);
      expect(await store.read(), isNull);
    },
  );

  test(
    'recording detail job retains provider and prior transcript on cancellation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final c =
          RecorderController(loadPersistedState: false, agentPlanAsr: service)
            ..speechProvider = SttProvider.agentPlan
            ..transcriptLanguage = 'fr'
            ..appleSourceLanguage = 'ja-JP';
      addTearDown(c.dispose);
      await c.saveAgentPlanKey(sentinel());
      final ref = RecordingReference(path: file.path);
      final work = c.transcribeRecording(ref);
      await transport.configured.future;
      transport.responses.add(_response({}));
      await transport.lastAudio.future;
      transport.responses.add(
        _response({
          'result': {'text': '保存文本'},
        }, flags: 3),
      );
      await work;
      expect(c.recordingView(ref).provider, SttProvider.agentPlan);
      expect(c.recordingView(ref).sourceLanguage, 'auto');
      expect(c.appleSourceLanguage, 'ja-JP');
      expect(c.transcriptLanguage, 'fr');
      transport = _Transport();
      final retry = c.transcribeRecording(ref);
      await transport.configured.future;
      expect(c.canCancelAgentPlan(ref), isTrue);
      c.cancelAgentPlan(ref);
      await retry;
      expect(c.recordingView(ref).text, '保存文本');
      expect(c.recordingView(ref).error, AgentPlanError.cancelled.message);
    },
  );
}
