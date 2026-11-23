import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Enkripsi/dekripsi vault backup dengan AES-256-GCM, kunci diturunkan dari
/// password via PBKDF2-HMAC-SHA256. Format berkas = JSON teks berisi parameter
/// + ciphertext base64 (mudah diperiksa, tahan korupsi sebagian).
const int _iterations = 120000;

String encryptVault(String plaintext, String password) {
  final salt = _randomBytes(16);
  final nonce = _randomBytes(12);
  final key = _deriveKey(password, salt, _iterations);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final ct = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
  return const JsonEncoder.withIndent('  ').convert({
    'magic': 'HEGIVAULT',
    'v': 1,
    'kdf': 'pbkdf2-hmac-sha256',
    'iter': _iterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(nonce),
    'ct': base64.encode(ct),
  });
}

/// Dekripsi. Melempar [FormatException] bila bukan vault, atau
/// [InvalidCipherTextException] bila password salah / berkas diubah.
String decryptVault(String fileText, String password) {
  final map = jsonDecode(fileText) as Map<String, dynamic>;
  if (map['magic'] != 'HEGIVAULT') {
    throw const FormatException('Bukan berkas backup HegiKetok.');
  }
  final iter = (map['iter'] as num?)?.toInt() ?? _iterations;
  final salt = base64.decode(map['salt'] as String);
  final nonce = base64.decode(map['nonce'] as String);
  final ct = base64.decode(map['ct'] as String);
  final key = _deriveKey(password, salt, iter);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  final plain = cipher.process(ct);
  return utf8.decode(plain);
}

Uint8List _deriveKey(String password, Uint8List salt, int iter) {
  final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iter, 32));
  return d.process(Uint8List.fromList(utf8.encode(password)));
}

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}
