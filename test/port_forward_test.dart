import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/ssh/port_forward.dart';

void main() {
  group('detectListeningPort', () {
    test('URL localhost', () {
      expect(detectListeningPort('  http://localhost:3000')?.port, 3000);
      expect(detectListeningPort('ready on http://127.0.0.1:4000/')?.port, 4000);
      expect(detectListeningPort('App: http://0.0.0.0:5173/')?.port, 5173);
    });

    test('frasa "listening/running on port"', () {
      expect(detectListeningPort('Listening on port 8080')?.port, 8080);
      expect(detectListeningPort('server started on :9229')?.port, 9229);
      expect(
          detectListeningPort('Now serving on http://localhost:1234')?.port,
          1234);
    });

    test('host:port di tengah baris', () {
      expect(detectListeningPort('bound 0.0.0.0:8000')?.port, 8000);
    });

    test('abaikan port umum non-aplikasi', () {
      expect(detectListeningPort('listening on port 22'), isNull);
      expect(detectListeningPort('https://localhost:443'), isNull);
      expect(detectListeningPort('http://localhost:80'), isNull);
    });

    test('baris tanpa port → null', () {
      expect(detectListeningPort('hello world'), isNull);
      expect(detectListeningPort(r'$ ls -la'), isNull);
      expect(detectListeningPort(''), isNull);
    });

    test('port di luar rentang diabaikan', () {
      expect(detectListeningPort('listening on port 999999'), isNull);
    });
  });
}
