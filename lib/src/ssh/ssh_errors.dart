// Satu tempat untuk menerjemahkan galat koneksi SSH menjadi pesan yang bisa
// ditindaklanjuti pengguna. Murni (tanpa jaringan) agar bisa diuji unit.
import '../models/ssh_credentials.dart';

/// Host key server ditolak (oleh pengguna, atau karena tak ada yang bisa
/// menyetujuinya). [changed] true bila key berbeda dari yang pernah dipercaya.
class HostKeyRejectedException implements Exception {
  const HostKeyRejectedException(this.hostPort, {this.changed = false});
  final String hostPort;
  final bool changed;
  @override
  String toString() => 'Host key $hostPort ditolak';
}

enum SshFailureKind {
  /// Server menolak login (username/password/key salah).
  auth,

  /// Server menutup koneksi sebelum login selesai — khasnya karena server
  /// sedang memblokir sementara alamat kita setelah beberapa login gagal.
  serverClosed,

  /// Port tertutup / tidak ada layanan SSH di sana.
  refused,

  /// Server tidak menjawab dalam batas waktu.
  timeout,

  /// Nama host tidak bisa di-resolve.
  hostNotFound,

  /// Host key ditolak (oleh pengguna, atau berubah).
  hostKey,

  /// Private key tidak terbaca / passphrase salah (gagal sebelum ke server).
  badKey,

  /// Jaringan tidak tersedia / rute terputus.
  network,

  other,
}

class SshFailure {
  const SshFailure(this.kind, this.message, {this.hint});

  final SshFailureKind kind;

  /// Satu kalimat: apa yang terjadi.
  final String message;

  /// Langkah perbaikan yang disarankan (opsional).
  final String? hint;

  /// Pesan + saran dalam satu baris.
  String get full => hint == null ? message : '$message $hint';

  /// true bila mengedit data host kemungkinan besar menyelesaikan masalah.
  bool get fixableByEditingHost =>
      kind == SshFailureKind.auth ||
      kind == SshFailureKind.hostNotFound ||
      kind == SshFailureKind.refused ||
      kind == SshFailureKind.badKey;

  @override
  String toString() => full;
}

/// Terjemahkan [error] menjadi [SshFailure]. [credentials] (bila ada) dipakai
/// untuk menyebut username/alamat yang BENAR-BENAR dipakai — supaya salah
/// ketik langsung terlihat.
SshFailure describeSshError(Object error, {SshCredentials? credentials}) {
  if (error is HostKeyRejectedException) {
    return error.changed
        ? SshFailure(
            SshFailureKind.hostKey,
            'Host key ${error.hostPort} BERUBAH dan tidak disetujui.',
            hint: 'Bisa jadi server dipasang ulang — atau ada pihak lain di '
                'tengah. Pastikan dulu sebelum menyetujui key baru.',
          )
        : const SshFailure(
            SshFailureKind.hostKey,
            'Host key server tidak disetujui.',
            hint: 'Sambungkan lagi dan setujui sidik jarinya bila kamu '
                'mengenalinya.',
          );
  }
  final raw = error.toString();
  final t = raw.toLowerCase();
  final user = credentials?.username;
  final target =
      credentials == null ? null : '${credentials.host}:${credentials.port}';

  if (t.contains('hostkey verification failed') ||
      t.contains('sshhostkeyerror') ||
      t.contains('host key')) {
    return const SshFailure(
      SshFailureKind.hostKey,
      'Host key server tidak disetujui.',
      hint: 'Sambungkan lagi dan setujui sidik jarinya bila kamu mengenalinya.',
    );
  }

  // Private key rusak / passphrase salah — terjadi sebelum bicara ke server.
  if (t.contains('passphrase') ||
      t.contains('invalid pem') ||
      t.contains('unsupported key') ||
      t.contains('unsupported cipher') ||
      (t.contains('formatexception') && credentials?.usesKey == true)) {
    return const SshFailure(
      SshFailureKind.badKey,
      'Private key tidak terbaca.',
      hint: 'Periksa berkas key dan passphrase-nya.',
    );
  }

  // Harus dicek sebelum 'auth' umum: pustaka SSH menamainya AuthAbort, tetapi
  // ini BUKAN password salah — server memutus sebelum sempat memeriksanya.
  if (t.contains('sshauthaborterror') ||
      t.contains('closed before authentication')) {
    return const SshFailure(
      SshFailureKind.serverClosed,
      'Server menutup koneksi sebelum login selesai.',
      hint: 'Bila tadi beberapa kali gagal login, server mungkin memblokir '
          'sementara alamatmu. Tunggu sekitar setengah menit, lalu coba '
          'lagi.',
    );
  }

  if (t.contains('auth')) {
    final who = (user == null || user.isEmpty) ? '' : ' untuk user "$user"';
    final usesKey = credentials?.usesKey ?? false;
    return SshFailure(
      SshFailureKind.auth,
      'Login ditolak$who.',
      hint: usesKey
          ? 'Periksa username, dan pastikan public key sudah terpasang di '
              'server.'
          : 'Periksa username dan password.',
    );
  }

  if (t.contains('refused')) {
    final where = target == null ? '' : ' di $target';
    return SshFailure(
      SshFailureKind.refused,
      'Koneksi ditolak$where.',
      hint: 'Periksa alamat dan port, dan pastikan layanan SSH aktif.',
    );
  }

  if (t.contains('timed out') || t.contains('timeout')) {
    final where = target ?? 'Server';
    return SshFailure(
      SshFailureKind.timeout,
      '$where tidak merespons (timeout).',
      hint: 'Periksa alamat, port, dan apakah VPN/jaringan ke server aktif.',
    );
  }

  if (t.contains('failed host lookup') || t.contains('nodename')) {
    final host = credentials?.host;
    return SshFailure(
      SshFailureKind.hostNotFound,
      host == null
          ? 'Host tidak ditemukan.'
          : 'Host "$host" tidak ditemukan.',
      hint: 'Periksa ejaan alamat server.',
    );
  }

  if (t.contains('network is unreachable') ||
      t.contains('no route to host') ||
      t.contains('connection reset') ||
      t.contains('broken pipe')) {
    return const SshFailure(
      SshFailureKind.network,
      'Jaringan ke server terputus.',
      hint: 'Periksa koneksi internet atau VPN.',
    );
  }

  final short = raw.length > 160 ? '${raw.substring(0, 160)}…' : raw;
  return SshFailure(SshFailureKind.other, 'Gagal menyambung: $short');
}

/// Peringatan (bukan larangan) untuk username yang kemungkinan salah ketik.
/// Mengembalikan null bila username tampak wajar.
///
/// Yang dianggap wajar: huruf, angka, `.` `_` `-`, akhiran `$`, serta bentuk
/// domain `DOMAIN\user` dan `user@domain`.
String? usernameWarning(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return null;
  if (RegExp(r'\s').hasMatch(name)) {
    return 'Username mengandung spasi — biasanya itu salah ketik.';
  }
  final ok = RegExp(r'^([A-Za-z0-9._-]+\\)?[A-Za-z0-9._-]+\$?(@[A-Za-z0-9.-]+)?$');
  if (!ok.hasMatch(name)) {
    final odd = name
        .split('')
        .where((c) => !RegExp(r'[A-Za-z0-9._\-\\@$]').hasMatch(c))
        .toSet()
        .join(' ');
    return odd.isEmpty
        ? 'Bentuk username ini tidak lazim — pastikan tidak salah ketik.'
        : 'Username mengandung karakter tak lazim ($odd). Pastikan password '
            'tidak ikut terketik di sini.';
  }
  if (name.length > 32) {
    return 'Username sangat panjang (${name.length} karakter) — pastikan '
        'tidak salah tempel.';
  }
  return null;
}

/// Peringatan untuk kolom alamat host yang kemungkinan salah isi. null = wajar.
String? hostAddressWarning(String raw) {
  final host = raw.trim();
  if (host.isEmpty) return null;
  if (RegExp(r'\s').hasMatch(host)) {
    return 'Alamat mengandung spasi — periksa lagi.';
  }
  if (host.contains('@')) {
    return 'Tulis alamatnya saja di sini; username diisi di kolom Username.';
  }
  if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(host)) {
    return 'Tulis tanpa awalan seperti "ssh://" atau "https://".';
  }
  // Port ditempel di alamat IPv4/nama host (bukan IPv6 yang memang ber-titik-dua).
  if (RegExp(r'^[^:]+:\d+$').hasMatch(host)) {
    return 'Port diisi di kolom Port, bukan di alamat.';
  }
  return null;
}
