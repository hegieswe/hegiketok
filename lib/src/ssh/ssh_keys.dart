// Manajemen SSH key: membuat keypair ed25519, menurunkan public key dari
// private key, dan memasang public key ke server (setara `ssh-copy-id`).
//
// Bagian parsing/format di sini murni (tanpa jaringan) agar bisa diuji unit.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pointycastle/digests/sha256.dart';

/// Informasi public key yang aman ditampilkan/dibagikan.
class SshPublicKeyInfo {
  const SshPublicKeyInfo({
    required this.type,
    required this.line,
    required this.fingerprint,
  });

  /// Jenis kunci, mis. `ssh-ed25519`, `ssh-rsa`.
  final String type;

  /// Satu baris format `authorized_keys`: `<type> <base64> [komentar]`.
  final String line;

  /// Sidik jari gaya OpenSSH: `SHA256:<base64 tanpa padding>`.
  final String fingerprint;
}

/// Keypair baru hasil [generateEd25519Key].
class GeneratedSshKey {
  const GeneratedSshKey({required this.privatePem, required this.public});

  /// Private key format OpenSSH (`-----BEGIN OPENSSH PRIVATE KEY-----`).
  /// RAHASIA — hanya untuk disimpan di Keychain.
  final String privatePem;
  final SshPublicKeyInfo public;
}

/// Private key tidak bisa dibaca (format salah, atau passphrase keliru).
class SshKeyException implements Exception {
  const SshKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Buat keypair ed25519 baru. [comment] ikut tersimpan di kedua kunci (biasanya
/// penanda asal, mis. `hegiketok@nama-host`).
GeneratedSshKey generateEd25519Key({String comment = ''}) {
  final clean = sanitizeKeyComment(comment);
  final signing = nacl.SigningKey.generate();
  final pair = OpenSSHEd25519KeyPair(
    Uint8List.fromList(signing.verifyKey.asTypedList),
    Uint8List.fromList(signing.asTypedList), // 64 byte: seed + public
    clean,
  );
  return GeneratedSshKey(
    privatePem: pair.toPem(),
    public: publicKeyInfoOf(pair, comment: clean),
  );
}

/// Turunkan public key dari [privatePem]. Melempar [SshKeyException] bila
/// kunci tak terbaca atau terenkripsi tanpa [passphrase] yang benar.
SshPublicKeyInfo describePrivateKey(
  String privatePem, {
  String? passphrase,
  String comment = '',
}) {
  final pem = privatePem.trim();
  if (pem.isEmpty) throw const SshKeyException('Private key kosong.');
  final List<SSHKeyPair> pairs;
  try {
    final pass = (passphrase == null || passphrase.isEmpty) ? null : passphrase;
    if (pass == null && SSHKeyPair.isEncryptedPem(pem)) {
      throw const SshKeyException(
          'Key ini dilindungi passphrase — isi passphrase untuk membacanya.');
    }
    pairs = SSHKeyPair.fromPem(pem, pass);
  } on SshKeyException {
    rethrow;
  } catch (_) {
    throw const SshKeyException(
        'Private key tidak terbaca (format tak dikenal atau passphrase salah).');
  }
  if (pairs.isEmpty) {
    throw const SshKeyException('Berkas tidak berisi private key.');
  }
  return publicKeyInfoOf(pairs.first, comment: comment);
}

/// Bentuk [SshPublicKeyInfo] dari sebuah keypair.
SshPublicKeyInfo publicKeyInfoOf(SSHKeyPair pair, {String comment = ''}) {
  final blob = pair.toPublicKey().encode();
  final type = _blobType(blob);
  final clean = sanitizeKeyComment(comment);
  final b64 = base64.encode(blob);
  return SshPublicKeyInfo(
    type: type,
    line: clean.isEmpty ? '$type $b64' : '$type $b64 $clean',
    fingerprint: fingerprintSha256(blob),
  );
}

/// Sidik jari SHA-256 gaya OpenSSH dari blob public key.
String fingerprintSha256(Uint8List blob) {
  final digest = SHA256Digest().process(blob);
  return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
}

// Blob public key SSH diawali string ber-prefiks panjang yang berisi tipenya.
String _blobType(Uint8List blob) {
  if (blob.length < 4) return 'unknown';
  final len = ByteData.sublistView(blob, 0, 4).getUint32(0);
  if (len <= 0 || 4 + len > blob.length) return 'unknown';
  return ascii.decode(blob.sublist(4, 4 + len), allowInvalid: true);
}

/// Komentar key yang aman: hanya huruf, angka, dan `@ . _ -`. Karakter lain
/// (termasuk spasi, kutip, baris baru) diganti `-` supaya tak pernah bisa
/// merusak `authorized_keys` atau perintah shell.
String sanitizeKeyComment(String raw) {
  final s = raw
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9@._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.length > 64 ? s.substring(0, 64) : s;
}

final RegExp _keyTypeRe = RegExp(
    r'^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)$');
final RegExp _base64Re = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

/// Validasi & normalkan satu baris public key (`<type> <base64> [komentar]`).
/// Mengembalikan baris bersih, atau null bila bukan public key yang sah.
/// Baris yang mengandung opsi (`command="…"` dsb.) atau baris baru ditolak.
String? normalizePublicKeyLine(String raw) {
  if (raw.contains('\n') || raw.contains('\r')) return null;
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  final type = parts[0];
  final b64 = parts[1];
  if (!_keyTypeRe.hasMatch(type)) return null;
  if (b64.length < 16 || !_base64Re.hasMatch(b64)) return null;
  final Uint8List blob;
  try {
    blob = base64.decode(b64);
  } catch (_) {
    return null;
  }
  // Tipe di dalam blob harus sama dengan yang tertulis di depan.
  if (_blobType(blob) != type) return null;
  final comment = sanitizeKeyComment(parts.skip(2).join('-'));
  return comment.isEmpty ? '$type $b64' : '$type $b64 $comment';
}

/// Penanda keluaran skrip pemasangan.
const String kKeyAddedMarker = 'HEGI_KEY_ADDED';
const String kKeyExistsMarker = 'HEGI_KEY_EXISTS';

/// Perintah shell (POSIX sh) untuk memasang [publicKeyLine] ke
/// `~/.ssh/authorized_keys` secara idempoten:
/// - membuat `~/.ssh` (700) dan `authorized_keys` (600) bila belum ada,
/// - tidak menambah bila kunci yang sama sudah terdaftar (komentar diabaikan),
/// - memastikan berkas diakhiri baris baru sebelum menambah.
///
/// Melempar [ArgumentError] bila barisnya bukan public key yang sah — baris
/// divalidasi ketat sehingga aman disisipkan dalam kutip tunggal.
String buildInstallKeyCommand(String publicKeyLine) {
  final line = normalizePublicKeyLine(publicKeyLine);
  if (line == null) {
    throw ArgumentError('Bukan public key SSH yang sah.');
  }
  final parts = line.split(' ');
  final identity = '${parts[0]} ${parts[1]}'; // tanpa komentar
  return [
    'umask 077',
    'mkdir -p "\$HOME/.ssh" || exit 11',
    'chmod 700 "\$HOME/.ssh" 2>/dev/null',
    'f="\$HOME/.ssh/authorized_keys"',
    'touch "\$f" || exit 12',
    'chmod 600 "\$f" 2>/dev/null',
    "if grep -qF -- '$identity' \"\$f\" 2>/dev/null; then echo $kKeyExistsMarker; exit 0; fi",
    'if [ -s "\$f" ] && [ -n "\$(tail -c 1 "\$f")" ]; then echo >> "\$f" || exit 13; fi',
    "printf '%s\\n' '$line' >> \"\$f\" || exit 13",
    'echo $kKeyAddedMarker',
  ].join('; ');
}

enum KeyInstallOutcome { added, alreadyPresent }

/// Pemasangan public key gagal di sisi server.
class KeyInstallException implements Exception {
  const KeyInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Tafsirkan keluaran skrip pemasangan.
KeyInstallOutcome parseInstallOutput(String output) {
  if (output.contains(kKeyAddedMarker)) return KeyInstallOutcome.added;
  if (output.contains(kKeyExistsMarker)) return KeyInstallOutcome.alreadyPresent;
  final detail = output.trim();
  throw KeyInstallException(detail.isEmpty
      ? 'Server tidak mengonfirmasi pemasangan key (cek izin tulis ~/.ssh).'
      : 'Server menolak: ${detail.length > 200 ? '${detail.substring(0, 200)}…' : detail}');
}

/// Pasang [publicKeyLine] ke akun yang sedang login pada [client].
Future<KeyInstallOutcome> installPublicKey(
  SSHClient client,
  String publicKeyLine,
) async {
  final script = buildInstallKeyCommand(publicKeyLine);
  // Skrip disuapkan lewat stdin ke `sh`, bukan sebagai argumen perintah —
  // supaya tetap jalan walau login shell pengguna bukan turunan sh (fish,
  // csh) dan tanpa lapisan kutip tambahan.
  final session = await client.execute('sh -s');
  final outFuture = session.stdout.toList();
  final errFuture = session.stderr.toList();
  session.stdin.add(Uint8List.fromList(utf8.encode('$script\n')));
  await session.stdin.close();
  final chunks = [...await outFuture, ...await errFuture];
  await session.done;
  final bytes = <int>[for (final c in chunks) ...c];
  return parseInstallOutput(utf8.decode(bytes, allowMalformed: true));
}
