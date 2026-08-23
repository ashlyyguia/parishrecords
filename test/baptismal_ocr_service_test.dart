import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parishrecord/services/baptismal_ocr_service.dart';

void main() {
  final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

  BaptismalOcrService serviceReturning(int status, Object body) {
    return BaptismalOcrService(
      client: MockClient((req) async => http.Response(jsonEncode(body), status)),
    );
  }

  test('parses a successful scan', () async {
    final svc = serviceReturning(200, {
      'success': true,
      'data': {
        'scanId': 's1',
        'rotation': 0,
        'warnings': <String>[],
        'rows': [
          {'lineNo': '1', 'fields': {'nameOfChild': {'value': 'JEZL', 'confidence': 0.9}}}
        ],
      },
    });
    final scan = await svc.scan(scanId: 's1', bytes: bytes, idToken: 't');
    expect(scan.rows, hasLength(1));
    expect(scan.rows.first.field('nameOfChild').value, 'JEZL');
  });

  test('sends the bearer token and base64 body', () async {
    late http.Request captured;
    final svc = BaptismalOcrService(client: MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({'success': true, 'data': {'scanId': 's1', 'rows': [], 'rotation': 0, 'warnings': []}}),
        200,
      );
    }));
    await svc.scan(scanId: 's1', bytes: bytes, idToken: 'TOKEN');
    expect(captured.headers['Authorization'], 'Bearer TOKEN');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['scanId'], 's1');
    expect(body['imageBase64'], base64Encode(bytes));
  });

  test('surfaces a typed failure with the server code', () async {
    final svc = serviceReturning(429, {
      'success': false, 'code': 'VISION_QUOTA', 'message': 'rate limited',
    });
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()
          .having((f) => f.code, 'code', 'VISION_QUOTA')
          .having((f) => f.retryable, 'retryable', true)),
    );
  });

  test('marks VISION_AUTH as not retryable', () async {
    final svc = serviceReturning(500, {
      'success': false, 'code': 'VISION_AUTH', 'message': 'not configured',
    });
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>().having((f) => f.retryable, 'retryable', false)),
    );
  });

  test('maps a network error to a retryable NETWORK failure', () async {
    final svc = BaptismalOcrService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()
          .having((f) => f.code, 'code', 'NETWORK')
          .having((f) => f.retryable, 'retryable', true)),
    );
  });

  test('maps an unparseable body to a retryable failure', () async {
    final svc = BaptismalOcrService(
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
    );
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
      throwsA(isA<BaptismalOcrFailure>()),
    );
  });

  test('fails fast without an auth token', () async {
    final svc = serviceReturning(200, {'success': true, 'data': {}});
    await expectLater(
      svc.scan(scanId: 's1', bytes: bytes, idToken: null),
      throwsA(isA<BaptismalOcrFailure>().having((f) => f.code, 'code', 'UNAUTHENTICATED')),
    );
  });
}
