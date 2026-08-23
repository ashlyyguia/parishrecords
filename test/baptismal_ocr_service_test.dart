import 'dart:async';
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

  group('OcrRecovery mapping', () {
    test('retry category: VISION_QUOTA, VISION_UNAVAILABLE, INTERNAL_ERROR, NETWORK, BAD_RESPONSE', () async {
      Future<void> expectRetry(BaptismalOcrService svc, String expectedCode) {
        return expectLater(
          svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
          throwsA(isA<BaptismalOcrFailure>()
              .having((f) => f.code, 'code', expectedCode)
              .having((f) => f.recovery, 'recovery', OcrRecovery.retry)
              .having((f) => f.retryable, 'retryable', true)),
        );
      }

      await expectRetry(
        serviceReturning(429, {'success': false, 'code': 'VISION_QUOTA', 'message': 'm'}),
        'VISION_QUOTA',
      );
      await expectRetry(
        serviceReturning(503, {'success': false, 'code': 'VISION_UNAVAILABLE', 'message': 'm'}),
        'VISION_UNAVAILABLE',
      );
      await expectRetry(
        serviceReturning(500, {'success': false, 'code': 'INTERNAL_ERROR', 'message': 'm'}),
        'INTERNAL_ERROR',
      );
      await expectRetry(
        BaptismalOcrService(client: MockClient((_) async => throw http.ClientException('offline'))),
        'NETWORK',
      );
      await expectRetry(
        BaptismalOcrService(client: MockClient((_) async => http.Response('not json', 502))),
        'BAD_RESPONSE',
      );
    });

    test('differentImage category: NO_TEXT_FOUND, IMAGE_INVALID, IMAGE_TOO_LARGE, LAYOUT_UNRECOGNIZED', () async {
      Future<void> expectDifferentImage(String code) {
        final svc = serviceReturning(400, {'success': false, 'code': code, 'message': 'm'});
        return expectLater(
          svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
          throwsA(isA<BaptismalOcrFailure>()
              .having((f) => f.code, 'code', code)
              .having((f) => f.recovery, 'recovery', OcrRecovery.differentImage)
              .having((f) => f.retryable, 'retryable', false)),
        );
      }

      await expectDifferentImage('NO_TEXT_FOUND');
      await expectDifferentImage('IMAGE_INVALID');
      await expectDifferentImage('IMAGE_TOO_LARGE');
      await expectDifferentImage('LAYOUT_UNRECOGNIZED');
    });

    test('signIn category: UNAUTHENTICATED', () async {
      final svc = serviceReturning(200, {'success': true, 'data': {}});
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: null),
        throwsA(isA<BaptismalOcrFailure>()
            .having((f) => f.code, 'code', 'UNAUTHENTICATED')
            .having((f) => f.recovery, 'recovery', OcrRecovery.signIn)
            .having((f) => f.retryable, 'retryable', false)),
      );
    });

    test('contactAdmin category: VISION_AUTH', () async {
      final svc = serviceReturning(500, {
        'success': false, 'code': 'VISION_AUTH', 'message': 'not configured',
      });
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>()
            .having((f) => f.code, 'code', 'VISION_AUTH')
            .having((f) => f.recovery, 'recovery', OcrRecovery.contactAdmin)
            .having((f) => f.retryable, 'retryable', false)),
      );
    });
  });

  group('edge cases', () {
    test('200 with {success:true} and no data key is BAD_RESPONSE', () async {
      final svc = serviceReturning(200, {'success': true});
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>().having((f) => f.code, 'code', 'BAD_RESPONSE')),
      );
    });

    test('200 with data present but not a Map (a list) is BAD_RESPONSE', () async {
      final svc = serviceReturning(200, {'success': true, 'data': [1, 2, 3]});
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>().having((f) => f.code, 'code', 'BAD_RESPONSE')),
      );
    });

    test('200 with data present but not a Map (a string) is BAD_RESPONSE', () async {
      final svc = serviceReturning(200, {'success': true, 'data': 'oops'});
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>().having((f) => f.code, 'code', 'BAD_RESPONSE')),
      );
    });

    test('non-200 with valid JSON but no code field falls back to BAD_RESPONSE', () async {
      final svc = serviceReturning(500, {'success': false, 'message': 'something broke'});
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>()
            .having((f) => f.code, 'code', 'BAD_RESPONSE')
            .having((f) => f.message, 'message', 'something broke')),
      );
    });

    test('empty imageBase64 is sent as-is and left to the backend to reject as IMAGE_INVALID', () async {
      late http.Request captured;
      final svc = BaptismalOcrService(client: MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({'success': false, 'code': 'IMAGE_INVALID', 'message': 'empty image'}),
          400,
        );
      }));
      final empty = Uint8List(0);
      await expectLater(
        svc.scan(scanId: 's1', bytes: empty, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>()
            .having((f) => f.code, 'code', 'IMAGE_INVALID')
            .having((f) => f.recovery, 'recovery', OcrRecovery.differentImage)),
      );
      // Pin the documented decision: the client does not pre-validate empty
      // bytes client-side. It still sends the request with an empty
      // base64 body and defers rejection to the backend.
      final sentBody = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sentBody['imageBase64'], '');
    });

    test('a short injected timeout against a client that never completes maps to a retryable NETWORK failure', () async {
      final neverCompletes = Completer<http.Response>();
      final svc = BaptismalOcrService(
        client: MockClient((_) => neverCompletes.future),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        svc.scan(scanId: 's1', bytes: bytes, idToken: 't'),
        throwsA(isA<BaptismalOcrFailure>()
            .having((f) => f.code, 'code', 'NETWORK')
            .having((f) => f.retryable, 'retryable', true)),
      );
    });
  });
}
