import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:school_vibe_argo/main.dart';

void main() {
  test('accepts successful JSON objects and a leading BOM', () {
    expect(ArgoResponseParser.decode(http.Response('{"success":true}', 200), 'Login')['success'], true);
    expect(ArgoResponseParser.decode(http.Response('\uFEFF {"data":[]}', 200), 'Dashboard')['data'], isEmpty);
  });

  for (final status in [200, 302, 403, 502, 503]) {
    test('HTML error identifies phase and HTTP $status without leaking response', () {
      expect(
        () => ArgoResponseParser.decode(http.Response('<html>SECRET_TOKEN</html>', status), 'Dashboard registro'),
        throwsA(predicate((e) => e.toString().contains('Dashboard registro') &&
            e.toString().contains('HTTP $status') && e.toString().contains('HTML') &&
            !e.toString().contains('SECRET_TOKEN'))),
      );
    });
  }

  for (final body in ['', '{broken', '[]', 'null', '42']) {
    test('rejects empty, malformed or unexpected JSON: $body', () {
      expect(() => ArgoResponseParser.decode(http.Response(body, 200), 'Token OAuth'), throwsException);
    });
  }

  test('rejects an HTTP error even if the body is valid JSON', () {
    expect(() => ArgoResponseParser.decode(http.Response('{"error":"SECRET"}', 401), 'Token OAuth'),
        throwsA(predicate((e) => e.toString().contains('HTTP 401') && !e.toString().contains('SECRET'))));
  });
}
