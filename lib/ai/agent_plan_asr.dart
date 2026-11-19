import 'dart:async';
import 'dart:io';

import '../audio/recording_pcm.dart';
import 'agent_plan_protocol.dart';
import 'agent_plan_transport.dart';
import 'stt_types.dart';

class AgentPlanAsr {
  AgentPlanAsr({
    this.transport = AgentPlanSocket.new,
    this.responseTimeout = const Duration(seconds: 45),
    this.packetInterval = const Duration(milliseconds: 200),
  });

  final AgentPlanTransport Function() transport;
  final Duration responseTimeout;
  final Duration packetInterval;
  _FileSession? _active;

  Future<SttResult> transcribePath(
    String path, {
    required String? apiKey,
    SttFileProgressCallback? onProgress,
  }) async {
    final key = apiKey?.trim();
    if (key == null ||
        key.isEmpty ||
        key.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw AgentPlanError.credentials;
    }
    if (_active != null) throw StateError('已有转写任务正在处理');
    final session = _FileSession(
      transport(),
      responseTimeout,
      packetInterval,
      StreamIterator(recordingPcm(path)),
      onProgress,
    );
    _active = session;
    try {
      unawaited(session.start(key));
      return await session.result.future;
    } finally {
      session.close();
      _active = null;
    }
  }

  void cancel() => _active?.fail(AgentPlanError.cancelled);
}

class _FileSession {
  _FileSession(
    this.transport,
    this.timeout,
    this.interval,
    this.audio,
    this.onProgress,
  );

  final AgentPlanTransport transport;
  final Duration timeout;
  final Duration interval;
  final StreamIterator<RecordingPcmPacket> audio;
  final SttFileProgressCallback? onProgress;
  final result = Completer<SttResult>();
  final transcript = AgentPlanTranscript();
  StreamSubscription<dynamic>? _subscription;
  Timer? _deadline;
  bool _acknowledged = false;
  bool _sentLast = false;
  bool _aborted = false;

  void _armTimeout() {
    _deadline?.cancel();
    _deadline = Timer(timeout, () => fail(AgentPlanError.timeout));
  }

  Future<void> start(String key) async {
    try {
      _armTimeout();
      if (!await audio.moveNext()) throw AgentPlanError.audio;
      if (result.isCompleted) return;
      final messages = await transport.connect(key);
      if (result.isCompleted) return;
      _subscription = messages.listen(
        _receive,
        onError: (Object _) => fail(AgentPlanError.network),
        onDone: () => fail(AgentPlanError.network),
      );
      _armTimeout();
      transport.send(AgentPlanProtocol.config());
    } catch (error) {
      fail(error);
    }
  }

  void _receive(dynamic message) {
    if (result.isCompleted) return;
    try {
      final frame = AgentPlanProtocol.decode(message);
      transcript.update(frame.payload, last: frame.last);
      if (frame.last) {
        if (!_sentLast) throw AgentPlanError.protocol;
        result.complete(
          SttResult(
            text: transcript.text.trim(),
            durationSec: transcript.durationSec,
          ),
        );
      } else {
        _armTimeout();
        if (!_acknowledged) {
          _acknowledged = true;
          unawaited(_sendAudio());
        }
      }
    } catch (error) {
      fail(error);
    }
  }

  Future<void> _sendAudio() async {
    try {
      var sequence = 2;
      do {
        if (result.isCompleted) return;
        final packet = audio.current;
        // nostream may be quiet during a long upload. Time out a stalled
        // operation, independently of the total recording length.
        _armTimeout();
        _sentLast = packet.consumed == packet.total;
        transport.send(
          AgentPlanProtocol.audio(sequence++, packet.pcm, last: _sentLast),
        );
        onProgress?.call(
          SttFileProgress(
            SttFileStage.uploading,
            uploadedBytes: packet.consumed,
            totalBytes: packet.total,
          ),
        );
        if (_sentLast) {
          _armTimeout();
          onProgress?.call(const SttFileProgress(SttFileStage.processing));
          return;
        }
        await Future<void>.delayed(interval);
        if (result.isCompleted) return;
      } while (await audio.moveNext());
      if (!result.isCompleted) throw AgentPlanError.audio;
    } catch (error) {
      fail(error);
    }
  }

  void fail(Object error) {
    if (result.isCompleted) return;
    _aborted = true;
    result.completeError(switch (error) {
      AgentPlanError() || RecordingAudioException() => error,
      FileSystemException() => AgentPlanError.audio,
      _ => AgentPlanError.network,
    });
  }

  void close() {
    _deadline?.cancel();
    transport.close(abort: _aborted);
    unawaited(_subscription?.cancel());
    unawaited(audio.cancel());
  }
}
