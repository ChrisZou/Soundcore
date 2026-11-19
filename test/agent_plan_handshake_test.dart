import 'dart:io';

import 'package:anker_recorder/ai/agent_plan_protocol.dart';
import 'package:anker_recorder/ai/agent_plan_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// The fake ends at the upgrade response. No TCP socket or DNS lookup is used.
class _Headers extends Fake implements HttpHeaders {
  final fields = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    fields[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => fields[name.toLowerCase()];
}

class _Response extends Fake implements HttpClientResponse {
  _Response(this.statusCode);
  @override
  final int statusCode;
  @override
  final _Headers headers = _Headers();
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.request);
  final _Request request;
  final urls = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return request;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'Plan upgrade sends only exclusive credentials and refuses redirects',
    () async {
      final marker = 'mock-${identityHashCode(Object())}';
      final response = _Response(HttpStatus.temporaryRedirect);
      response.headers.set('x-tt-logid', marker);
      final request = _Request(response);
      final client = _Client(request);
      final logs = <String?>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message);
      addTearDown(() => debugPrint = original);
      await HttpOverrides.runZoned(() async {
        final transport = AgentPlanSocket();
        try {
          await expectLater(
            transport.connect(marker),
            throwsA(AgentPlanError.protocol),
          );
        } finally {
          transport.close();
        }
      }, createHttpClient: (_) => client);
      expect(client.urls, [
        Uri.parse(AgentPlanProtocol.endpoint).replace(scheme: 'https'),
      ]);
      expect(request.followRedirects, isFalse);
      final fields = request.headers.fields;
      expect(fields['x-api-key'] == marker, isTrue);
      expect(fields.entries.where((entry) => entry.value == marker).length, 1);
      expect(fields['x-api-resource-id'], 'volc.seedasr.sauc.duration');
      expect(fields['x-api-sequence'], '-1');
      expect(fields['x-api-connect-id'], matches(r'^[0-9a-f-]{36}$'));
      expect(fields['x-api-connect-id'], fields['x-api-request-id']);
      expect(fields.containsKey('authorization'), isFalse);
      expect(logs.any((line) => line?.contains(marker) == true), isFalse);
    },
  );
}
