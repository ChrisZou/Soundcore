import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum AgentPlanError implements Exception {
  credentials('Agent Plan 鉴权失败，请检查专属 API Key 和访问权限'),
  limit('Agent Plan 请求受限，请稍后重试'),
  protocol('Agent Plan 协议错误，请重试'),
  network('无法连接 Agent Plan，请检查网络后重试'),
  timeout('Agent Plan 响应超时，请重试'),
  audio('Agent Plan 无法识别此录音，请检查音频格式'),
  service('Agent Plan 服务暂时不可用，请重试'),
  cancelled('转写已取消，可重试');

  const AgentPlanError(this.message);
  final String message;
  @override
  String toString() => message;

  static AgentPlanError handshake(int status) => switch (status) {
    401 || 403 => credentials,
    429 => limit,
    >= 500 => service,
    _ => protocol,
  };

  // Volcengine's streaming ASR error table. File-API codes do not apply.
  static AgentPlanError server(int code) => switch (code) {
    45000001 || 45000091 => protocol,
    45000002 || 45000151 => audio,
    45000081 || 55001010 => timeout,
    _ => service,
  };
}

class AgentPlanProtocol {
  static const endpoint =
      'wss://openspeech.bytedance.com/api/v3/plan/sauc/bigmodel_nostream';
  static const resourceId = 'volc.seedasr.sauc.duration';

  static Uint8List config() => _encode(
    1,
    1,
    utf8.encode(
      jsonEncode({
        'user': {'uid': 'soundcore-manager'},
        'audio': {
          'format': 'pcm',
          'codec': 'raw',
          'rate': 16000,
          'bits': 16,
          'channel': 1,
        },
        'request': {
          'model_name': 'bigmodel',
          'enable_itn': true,
          'enable_punc': true,
          'enable_ddc': true,
          'show_utterances': true,
          'enable_nonstream': false,
          'result_type': 'full',
        },
      }),
    ),
  );

  static Uint8List audio(int sequence, Uint8List pcm, {required bool last}) =>
      _encode(2, last ? -sequence : sequence, pcm);

  static Uint8List _encode(int type, int seq, List<int> bytes) {
    final payload = gzip.encode(bytes);
    final frame = Uint8List(12 + payload.length);
    frame.setAll(0, [0x11, type << 4 | (seq < 0 ? 3 : 1), 0x11, 0]);
    ByteData.sublistView(frame)
      ..setInt32(4, seq)
      ..setUint32(8, payload.length);
    frame.setAll(12, payload);
    return frame;
  }

  static ({bool last, Map<String, dynamic> payload}) decode(dynamic message) {
    try {
      if (message is! List<int>) throw AgentPlanError.protocol;
      final bytes = message is Uint8List
          ? message
          : Uint8List.fromList(message);
      final data = ByteData.sublistView(bytes);
      final type = bytes[1] >> 4;
      final flags = bytes[1] & 15;
      var offset = (bytes[0] & 15) * 4;
      if (bytes[0] >> 4 != 1 ||
          offset < 4 ||
          flags > 7 ||
          (type != 9 && type != 15)) {
        throw AgentPlanError.protocol;
      }
      final last = (flags & 2) != 0;
      if (flags & 1 != 0) {
        // The final marker is the flag bit on a response, independently of
        // the echoed sequence. Only outbound final audio requires a negative int.
        data.getInt32(offset);
        offset += 4;
      }
      if (flags & 4 != 0) offset += 4; // optional event in the Plan parser
      final error = type == 15 ? data.getInt32(offset) : null;
      if (error != null) offset += 4;
      final length = data.getUint32(offset);
      offset += 4;
      if (length != bytes.length - offset) throw AgentPlanError.protocol;
      if (error != null) throw AgentPlanError.server(error);
      if (length == 0) return (last: last, payload: <String, dynamic>{});
      if (bytes[2] >> 4 != 1) throw AgentPlanError.protocol;
      final wire = Uint8List.sublistView(bytes, offset);
      final payload = switch (bytes[2] & 15) {
        0 => wire,
        1 => gzip.decode(wire),
        _ => throw AgentPlanError.protocol,
      };
      return (
        last: last,
        payload: jsonDecode(utf8.decode(payload)) as Map<String, dynamic>,
      );
    } on AgentPlanError {
      rethrow;
    } catch (_) {
      // Decoder errors can contain the entire server response.
      throw AgentPlanError.protocol;
    }
  }
}

/// With result_type=full each snapshot replaces the previous one. Keep only
/// definite speech between packets in case the final frame is an empty marker.
class AgentPlanTranscript {
  String text = '';
  double? durationSec;

  void update(Map<String, dynamic> payload, {required bool last}) {
    try {
      final ms = payload['audio_info']?['duration'] as num?;
      if (ms != null) durationSec = ms / 1000;
      final result = payload['result'];
      if (result == null) return;
      final parts = result is List ? result : [result];
      final snapshot = StringBuffer();
      for (final part in parts) {
        if (last &&
            part['text'] is String &&
            (part['text'] as String).isNotEmpty) {
          snapshot.write(part['text']);
          continue;
        }
        for (final utterance in part['utterances'] as List? ?? const []) {
          if (last || utterance['definite'] == true) {
            snapshot.write(utterance['text'] as String);
          }
        }
      }
      if (snapshot.isNotEmpty) text = snapshot.toString();
    } catch (_) {
      throw AgentPlanError.protocol;
    }
  }
}
