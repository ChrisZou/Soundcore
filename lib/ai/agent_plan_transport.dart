import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'agent_plan_protocol.dart';

/// Owns one connection, including an upgrade that is still in flight.
abstract interface class AgentPlanTransport {
  Future<Stream<dynamic>> connect(String key);
  void send(Uint8List frame);
  void close({bool abort = false});
}

class AgentPlanSocket implements AgentPlanTransport {
  final _client = HttpClient();
  WebSocket? _socket;
  Socket? _raw;
  bool _closed = false;

  @override
  Future<Stream<dynamic>> connect(String key) async {
    try {
      final endpoint = Uri.parse(AgentPlanProtocol.endpoint);
      final request = await _client.getUrl(endpoint.replace(scheme: 'https'));
      if (_closed) throw AgentPlanError.cancelled;
      // Never forward a Plan credential on a redirect.
      request.followRedirects = false;
      final id = const Uuid().v4();
      final random = Random.secure();
      final nonce = base64.encode(
        List.generate(16, (_) => random.nextInt(256)),
      );
      request.headers
        ..set('Connection', 'Upgrade')
        ..set('Upgrade', 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', nonce)
        ..set('X-Api-Key', key)
        ..set('X-Api-Resource-Id', AgentPlanProtocol.resourceId)
        ..set('X-Api-Request-Id', id)
        ..set('X-Api-Connect-Id', id)
        ..set('X-Api-Sequence', '-1');
      final response = await request.close();
      final logId = response.headers.value('x-tt-logid');
      if (logId != null &&
          RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(logId) &&
          !logId.contains(key)) {
        debugPrint('[Agent Plan] X-Tt-Logid=$logId');
      }
      if (response.statusCode != HttpStatus.switchingProtocols) {
        throw AgentPlanError.handshake(response.statusCode);
      }
      final accept = base64.encode(
        sha1
            .convert(
              ascii.encode('${nonce}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
            )
            .bytes,
      );
      final connection = response.headers['connection']
          ?.join(',')
          .toLowerCase()
          .split(',');
      if (response.headers.value('sec-websocket-accept') != accept ||
          response.headers.value('upgrade')?.toLowerCase() != 'websocket' ||
          connection?.any((value) => value.trim() == 'upgrade') != true) {
        throw AgentPlanError.protocol;
      }
      final raw = await response.detachSocket();
      if (_closed) {
        raw.destroy();
        throw AgentPlanError.cancelled;
      }
      _raw = raw;
      return _socket = WebSocket.fromUpgradedSocket(
        raw,
        serverSide: false,
        compression: CompressionOptions.compressionOff,
      );
    } on AgentPlanError {
      rethrow;
    } catch (_) {
      throw AgentPlanError.network;
    }
  }

  @override
  void send(Uint8List frame) => _socket!.add(frame);

  @override
  void close({bool abort = false}) {
    _closed = true;
    _client.close(force: true);
    final raw = _raw;
    final socket = _socket;
    if (abort) {
      raw?.destroy();
    } else if (socket != null) {
      unawaited(
        socket
            .close()
            .timeout(const Duration(seconds: 1))
            .catchError((Object _) {})
            .whenComplete(() => raw?.destroy()),
      );
    }
  }
}
