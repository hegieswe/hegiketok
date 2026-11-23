import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

/// Versi aplikasi saat ini. HARUS sama dengan `version:` di pubspec.yaml
/// (bagian sebelum `+`); dijaga oleh test `update_checker_test.dart`.
const String kAppVersion = '1.0.0';

/// Repo GitHub tempat rilis dipublikasikan (owner/repo). Ganti sesuai repo
/// kamu; pemeriksaan pembaruan menanyakan rilis terbaru di sini.
const String kUpdateRepo = 'hegieswe/hegiketok';

/// Satu berkas terlampir pada rilis GitHub.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  final String name;

  /// `browser_download_url` (https://github.com/…/releases/download/…).
  final String url;

  /// Ukuran dalam byte menurut GitHub (0 bila tak diketahui).
  final int size;

  /// Digest SHA-256 heksadesimal huruf kecil bila GitHub menyertakannya.
  final String? sha256;
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes,
    this.asset,
  });

  final String version;

  /// Halaman rilis (untuk dibuka di browser).
  final String url;
  final String? notes;

  /// Paket macOS yang bisa diunduh langsung (null bila rilis tak punya).
  final ReleaseAsset? asset;
}

/// Hasil pemeriksaan pembaruan.
sealed class UpdateResult {}

class UpdateAvailable extends UpdateResult {
  UpdateAvailable(this.info);
  final UpdateInfo info;
}

class UpdateUpToDate extends UpdateResult {}

class UpdateFailed extends UpdateResult {
  UpdateFailed(this.message);
  final String message;
}

/// Tanya rilis terbaru di GitHub dan bandingkan dengan [kAppVersion].
/// Tidak mengirim data pengguna apa pun — hanya GET publik.
Future<UpdateResult> checkForUpdate({
  String repo = kUpdateRepo,
  String current = kAppVersion,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final uri = Uri.https('api.github.com', '/repos/$repo/releases/latest');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(uri).timeout(timeout);
    req.headers.set(HttpHeaders.userAgentHeader, 'HegiKetok-UpdateCheck');
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode == 404) {
      await resp.drain<void>();
      return UpdateFailed('Belum ada rilis di $repo.');
    }
    if (resp.statusCode == 403 || resp.statusCode == 429) {
      await resp.drain<void>();
      return UpdateFailed('GitHub membatasi permintaan. Coba lagi nanti.');
    }
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      return UpdateFailed('Server menjawab ${resp.statusCode}.');
    }
    final body = await resp.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return UpdateFailed('Format rilis tak dikenali.');
    }
    return parseLatestRelease(decoded, current: current);
  } on TimeoutException {
    return UpdateFailed('Tak ada jawaban dari GitHub (timeout).');
  } on SocketException {
    return UpdateFailed('Tak bisa menghubungi GitHub — cek koneksi internet.');
  } catch (e) {
    return UpdateFailed('Tak bisa memeriksa: $e');
  } finally {
    client.close(force: true);
  }
}

/// Urai JSON `releases/latest` GitHub menjadi [UpdateResult]. Murni (tanpa
/// jaringan) supaya bisa diuji.
UpdateResult parseLatestRelease(
  Map<String, dynamic> json, {
  String current = kAppVersion,
}) {
  final tag = (json['tag_name'] as String?)?.trim() ?? '';
  final latest =
      (tag.startsWith('v') || tag.startsWith('V')) ? tag.substring(1) : tag;
  if (latest.isEmpty || !RegExp(r'^\d+(\.\d+)*').hasMatch(latest)) {
    return UpdateFailed('Format rilis tak dikenali.');
  }
  if (!isNewerVersion(latest, current)) return UpdateUpToDate();

  final url = (json['html_url'] as String?) ?? '';
  final notes = (json['body'] as String?)?.trim();
  return UpdateAvailable(UpdateInfo(
    version: latest,
    url: _isGithubHttps(url) ? url : '',
    notes: (notes == null || notes.isEmpty) ? null : notes,
    asset: pickMacAsset(json['assets']),
  ));
}

/// Pilih paket macOS dari daftar `assets` rilis: `.dmg` diutamakan, lalu
/// `.zip` yang namanya menyebut mac/darwin/osx. Aset dengan URL di luar
/// github.com diabaikan.
ReleaseAsset? pickMacAsset(Object? assets) {
  if (assets is! List) return null;
  ReleaseAsset? dmg;
  ReleaseAsset? zip;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = (a['name'] as String?) ?? '';
    final url = (a['browser_download_url'] as String?) ?? '';
    if (name.isEmpty || !_isGithubHttps(url)) continue;
    final lower = name.toLowerCase();
    final asset = ReleaseAsset(
      name: name,
      url: url,
      size: (a['size'] as num?)?.toInt() ?? 0,
      sha256: _sha256Of(a['digest']),
    );
    if (lower.endsWith('.dmg')) {
      dmg ??= asset;
    } else if (lower.endsWith('.zip') &&
        (lower.contains('mac') ||
            lower.contains('darwin') ||
            lower.contains('osx'))) {
      zip ??= asset;
    }
  }
  return dmg ?? zip;
}

String? _sha256Of(Object? digest) {
  if (digest is! String) return null;
  final d = digest.trim().toLowerCase();
  if (!d.startsWith('sha256:')) return null;
  final hex = d.substring('sha256:'.length);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
}

bool _isGithubHttps(String url) {
  final u = Uri.tryParse(url);
  return u != null && u.scheme == 'https' && u.host == 'github.com';
}

/// Bandingkan versi semver sederhana (x.y.z). true bila [a] > [b].
bool isNewerVersion(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] > pb[i];
  }
  return false;
}

List<int> _parts(String v) {
  final core = v.split('+').first.split('-').first;
  final nums = core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  while (nums.length < 3) {
    nums.add(0);
  }
  return nums;
}

// ─────────────────────────── Unduhan paket ───────────────────────────

/// Unduhan dibatalkan pengguna.
class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();
}

/// Unduhan gagal atau berkas tak lolos verifikasi.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Nama berkas aman dari nama aset: hanya komponen terakhir, tanpa pemisah
/// path atau awalan titik (mencegah menulis di luar folder tujuan).
String safeAssetFileName(String name) {
  var base = name.replaceAll('\\', '/').split('/').last.trim();
  base = base.replaceAll(RegExp(r'[\x00-\x1f:]'), '_');
  while (base.startsWith('.')) {
    base = base.substring(1);
  }
  return base.isEmpty ? 'HegiKetok-update' : base;
}

/// Unduh [asset] ke [directory] sambil melaporkan kemajuan (0..1, atau null
/// bila ukuran total tak diketahui). Berkas ditulis ke `<nama>.part` dulu dan
/// baru diganti nama setelah ukuran — dan SHA-256 bila GitHub menyertakannya —
/// cocok. [isCancelled] diperiksa tiap potongan data.
Future<File> downloadReleaseAsset(
  ReleaseAsset asset, {
  required Directory directory,
  void Function(double? fraction)? onProgress,
  bool Function()? isCancelled,
  HttpClient? httpClient,
}) async {
  final uri = Uri.parse(asset.url);
  if (uri.scheme != 'https' && httpClient == null) {
    throw const UpdateDownloadException('URL unduhan tidak aman.');
  }
  await directory.create(recursive: true);
  final fileName = safeAssetFileName(asset.name);
  final target = File('${directory.path}/$fileName');
  final part = File('${directory.path}/$fileName.part');

  final client = httpClient ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  IOSink? sink;
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, 'HegiKetok-UpdateCheck');
    req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw UpdateDownloadException(
          'Server menjawab ${resp.statusCode} saat mengunduh.');
    }
    final total = resp.contentLength > 0
        ? resp.contentLength
        : (asset.size > 0 ? asset.size : -1);

    sink = part.openWrite();
    final digest = SHA256Digest();
    var received = 0;
    onProgress?.call(total > 0 ? 0 : null);
    await for (final chunk in resp.timeout(const Duration(seconds: 45))) {
      if (isCancelled?.call() ?? false) {
        throw const UpdateDownloadCancelled();
      }
      final bytes =
          chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
      sink.add(bytes);
      received += bytes.length;
      onProgress?.call(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (asset.size > 0 && received != asset.size) {
      throw UpdateDownloadException(
          'Unduhan tidak lengkap ($received dari ${asset.size} byte).');
    }
    final expected = asset.sha256;
    if (expected != null) {
      final out = Uint8List(digest.digestSize);
      digest.doFinal(out, 0);
      final actual =
          out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (actual != expected) {
        throw const UpdateDownloadException(
            'Checksum SHA-256 tidak cocok — berkas dibuang demi keamanan.');
      }
    }

    if (await target.exists()) await target.delete();
    return await part.rename(target.path);
  } on TimeoutException {
    throw const UpdateDownloadException('Unduhan terhenti (timeout).');
  } on SocketException {
    throw const UpdateDownloadException(
        'Koneksi terputus saat mengunduh.');
  } finally {
    try {
      await sink?.close();
    } catch (_) {}
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {}
    }
    if (httpClient == null) client.close(force: true);
  }
}
