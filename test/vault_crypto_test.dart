import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_term/src/data/vault_crypto.dart';

void main() {
  group('vault crypto', () {
    test('round-trip: enkripsi lalu dekripsi mengembalikan teks asli', () {
      const plain = '{"hosts":[{"id":"a","secret":"rahasia"}]}';
      final enc = encryptVault(plain, 'kataSandi123');
      expect(enc, contains('HEGIVAULT'));
      expect(enc, isNot(contains('rahasia'))); // tak bocor sebagai plaintext
      final dec = decryptVault(enc, 'kataSandi123');
      expect(dec, plain);
    });

    test('password salah → melempar', () {
      final enc = encryptVault('data penting', 'benar');
      expect(() => decryptVault(enc, 'salah'), throwsA(anything));
    });

    test('bukan berkas vault → FormatException', () {
      expect(() => decryptVault('{"foo":1}', 'x'),
          throwsA(isA<FormatException>()));
    });

    test('dua enkripsi teks sama menghasilkan ciphertext berbeda (salt/nonce acak)',
        () {
      final a = encryptVault('halo', 'pw123456');
      final b = encryptVault('halo', 'pw123456');
      expect(a, isNot(equals(b)));
    });
  });
}
