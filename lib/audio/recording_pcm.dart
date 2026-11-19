import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ogg_opus.dart';
import 'opus_pcm_decoder.dart';

class RecordingAudioException implements Exception {
  const RecordingAudioException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One packet of 16 kHz mono PCM16 LE, with progress in source bytes.
typedef RecordingPcmPacket = ({Uint8List pcm, int consumed, int total});

/// Read the recording formats produced by the D3200 export pipeline without
/// changing the original, creating a sidecar, or buffering the entire take.
Stream<RecordingPcmPacket> recordingPcm(String path) async* {
  final file = await File(path).open();
  try {
    final total = await file.length();
    if (total == 0) throw const RecordingAudioException('录音文件为空');
    final prefix = await file.read(12);
    if (path.endsWith('.opus.bin')) {
      throw const RecordingAudioException('加密录音无法转写，请重新下载并解密');
    }
    if (OggOpus.isWav(prefix)) {
      yield* _readWave(file, total);
    } else if (path.endsWith('.opus') && !OggOpus.isOgg(prefix)) {
      await file.setPosition(0);
      yield* _readOpus(file, total);
    } else {
      throw const RecordingAudioException('无法转换此录音格式，请选择设备原始 Opus 或 PCM WAV');
    }
  } finally {
    await file.close();
  }
}

Stream<RecordingPcmPacket> _readOpus(RandomAccessFile file, int total) async* {
  final decoder = OpusPcmDecoder();
  try {
    var consumed = 0;
    while (consumed < total) {
      final block = await file.read(
        math.min(10 * OggOpus.frameSize, total - consumed),
      );
      if (block.isEmpty) throw const RecordingAudioException('录音文件不完整');
      final output = BytesBuilder(copy: false);
      for (var i = 0; i < block.length; i += OggOpus.frameSize) {
        final pcm = decoder.decodeFrame(
          Uint8List.sublistView(
            block,
            i,
            math.min(i + OggOpus.frameSize, block.length),
          ),
        );
        if (pcm == null) throw const RecordingAudioException('无法解码设备 Opus 录音');
        output.add(pcm);
      }
      consumed += block.length;
      yield (pcm: output.takeBytes(), consumed: consumed, total: total);
    }
  } finally {
    decoder.dispose();
  }
}

Stream<RecordingPcmPacket> _readWave(RandomAccessFile file, int length) async* {
  const invalid = RecordingAudioException('WAV 录音不完整或格式无效');
  var channels = 0;
  var ratio = 0;
  var offset = 12;
  while (offset + 8 <= length) {
    await file.setPosition(offset);
    final header = await file.read(8);
    if (header.length != 8) throw invalid;
    final id = String.fromCharCodes(header, 0, 4);
    final size = ByteData.sublistView(header).getUint32(4, Endian.little);
    offset += 8;
    if (offset + size > length) throw invalid;
    if (id == 'fmt ') {
      if (size < 16) throw invalid;
      final format = ByteData.sublistView(await file.read(16));
      final rate = format.getUint32(4, Endian.little);
      channels = format.getUint16(2, Endian.little);
      if (format.getUint16(0, Endian.little) != 1 ||
          format.getUint16(14, Endian.little) != 16 ||
          ![1, 2].contains(channels) ||
          ![16000, 32000, 48000].contains(rate)) {
        throw const RecordingAudioException(
          '仅支持 16、32 或 48 kHz 的单声道或双声道 16 位 PCM WAV',
        );
      }
      if (format.getUint16(12, Endian.little) != channels * 2) throw invalid;
      ratio = rate ~/ 16000;
    } else if (id == 'data') {
      if (ratio == 0 || size == 0 || size % (channels * 2) != 0) throw invalid;
      var consumed = 0;
      final stride = ratio * channels * 2;
      while (consumed < size) {
        final count = math.min(3200 * stride, size - consumed);
        final block = await file.read(count);
        if (block.length != count) throw invalid;
        consumed += count;
        yield (pcm: _downmix(block, stride), consumed: consumed, total: size);
      }
      return;
    }
    offset += size + (size & 1);
  }
  throw invalid;
}

Uint8List _downmix(Uint8List block, int stride) {
  if (stride == 2) return block;
  final input = ByteData.sublistView(block);
  final output = ByteData(((block.length + stride - 1) ~/ stride) * 2);
  // Average all channels and source samples in each output sample interval.
  for (var i = 0, j = 0; i < block.length; i += stride, j += 2) {
    final end = math.min(i + stride, block.length);
    var sum = 0;
    for (var k = i; k < end; k += 2) {
      sum += input.getInt16(k, Endian.little);
    }
    output.setInt16(j, sum ~/ ((end - i) ~/ 2), Endian.little);
  }
  return output.buffer.asUint8List();
}
