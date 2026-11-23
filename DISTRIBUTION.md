# Distribusi HegiKetok

Cara merilis HegiKetok dan cara pengguna memasang serta memperbaruinya.

Model yang dipakai sekarang: **tanda tangan ad-hoc** (gratis, tanpa akun Apple
Developer) untuk pemakaian sendiri atau tim kecil, dengan pembaruan lewat
**GitHub Releases**. Jalur Developer ID + notarisasi untuk distribusi publik
sudah disiapkan di skrip yang sama; lihat [bagian terakhir](#naik-ke-developer-id-distribusi-publik).

## Ringkasan

| Langkah | Perintah |
|---|---|
| Naikkan versi | ubah `version:` di `pubspec.yaml` **dan** `kAppVersion` di `lib/src/features/updates/update_checker.dart` |
| Build + tanda tangan + kemas | `./scripts/release_macos.sh` |
| Terbitkan | `git tag v1.1.0 && git push --tags` (CI membuat GitHub Release) |
| Pengguna memperbarui | Settings → **Periksa pembaruan** → **Unduh & buka** |

## Repo GitHub

Kode dan rilis ada di <https://github.com/hegieswe/hegiketok>. Updater dalam
app menanyakan rilis terbaru ke repo yang tertulis di `kUpdateRepo`
(`lib/src/features/updates/update_checker.dart`), yaitu `hegieswe/hegiketok`.

Repo harus tetap **publik** selama updater dipakai: ia memanggil API GitHub
tanpa token, jadi rilis di repo privat tidak terlihat (app melaporkan "Belum
ada rilis"). Sampai rilis pertama diterbitkan, jawaban itu juga yang muncul.

## Merilis versi baru

### 1. Naikkan versi

Dua tempat, harus sama (bagian sebelum `+`):

```yaml
# pubspec.yaml
version: 1.1.0+2
```

```dart
// lib/src/features/updates/update_checker.dart
const String kAppVersion = '1.1.0';
```

Kalau lupa salah satunya, `flutter test` gagal (`update_checker_test.dart`) dan
`release_macos.sh` berhenti sebelum build. Itu disengaja: versi yang tidak
selaras membuat app salah menilai apakah ada pembaruan.

### 2. Build lokal

```bash
./scripts/release_macos.sh
```

Skrip menjalankan `flutter analyze` dan `flutter test`, membangun release,
menandatangani ad-hoc (framework dulu, lalu `.app` dengan
`macos/Runner/Release.entitlements`), memverifikasi tanda tangan, lalu mengemas:

```
dist/HegiKetok-1.1.0-macos.dmg   ← berisi app + pintasan Applications
dist/HegiKetok-1.1.0-macos.zip
dist/SHA256SUMS.txt
```

`SKIP_CHECKS=1 ./scripts/release_macos.sh` melewati analyze dan test.

### 3. Terbitkan

```bash
git tag v1.1.0
git push --tags
```

`.github/workflows/release.yml` membangun macOS, Linux, dan Windows, lalu
membuat GitHub Release berisi semua paket. Tag harus berbentuk `vX.Y.Z`.

Tanpa CI, unggah isi `dist/` secara manual ke rilis baru di GitHub dengan tag
yang sama. Nama `.dmg` jangan diubah: updater memilih aset `.dmg`, atau `.zip`
yang namanya mengandung `mac`.

> Workflow CI belum pernah dijalankan. Periksa hasil run pertamanya sebelum
> mengandalkannya.

## Memasang di Mac lain (tanda tangan ad-hoc)

App bertanda tangan ad-hoc berjalan normal di Mac tempat ia dibangun. Di Mac
lain, macOS menandai berkas yang datang lewat browser, AirDrop, atau aplikasi
pesan sebagai "dikarantina" dan menolak membukanya pada percobaan pertama.
Izinkan satu kali:

1. Buka `.dmg`, seret **HegiKetok** ke **Applications**.
2. Buka HegiKetok. macOS menampilkan peringatan; tutup peringatannya.
3. **System Settings → Privacy & Security**, gulir ke bawah, klik **Open
   Anyway** di samping HegiKetok, lalu konfirmasi.

Atau lewat Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/HegiKetok.app
```

Setelah itu app terbuka seperti biasa. Di macOS 14 dan lebih lama, klik kanan
app → **Open** juga bisa.

## Pembaruan di dalam app

- **Settings → Periksa pembaruan** menanyakan rilis terbaru. Bila ada versi
  baru, dialog menampilkan catatan rilis dan tombol **Unduh & buka**.
- Paket diunduh ke folder **Downloads**. Ukurannya dicocokkan dengan data
  GitHub, dan checksum SHA-256 diverifikasi bila GitHub menyertakannya. Berkas
  yang tidak cocok dibuang.
- Setelah `.dmg` terbuka: tutup HegiKetok, seret versi baru ke Applications
  (timpa yang lama), buka kembali. Pemasangan tidak otomatis — mengganti app
  yang sedang berjalan butuh framework seperti Sparkle, yang sengaja tidak
  dipakai agar app tetap ringan.
- **Periksa otomatis** (Settings, bisa dimatikan) menjalankan pemeriksaan yang
  sama paling sering sekali per 24 jam saat app dibuka, dan hanya memberi tahu
  bila ada versi baru. Yang dikirim hanya satu permintaan GET publik ke
  `api.github.com`; tidak ada data pengguna.

### Yang perlu diketahui soal ad-hoc

- **Keychain bertanya lagi setelah pembaruan.** Rahasia host disimpan di
  Keychain, yang mengikat izin ke tanda tangan app. Tanda tangan ad-hoc berubah
  setiap build, jadi setelah memperbarui macOS akan meminta izin lagi. Pilih
  **Always Allow**. Datanya tidak hilang.
- **Unduhan lewat app biasanya tidak dikarantina**, sehingga langkah "Open
  Anyway" hanya perlu untuk pemasangan pertama dari browser. Ini perilaku
  macOS yang belum diuji di Mac kedua; kalau peringatan tetap muncul, ulangi
  langkah di atas.

## Entitlements

`macos/Runner/Release.entitlements`:

| Kunci | Nilai | Alasan |
|---|---|---|
| `com.apple.security.app-sandbox` | `false` | Terminal harus menjalankan shell dan proses lokal |
| `com.apple.security.network.client` | `true` | Koneksi SSH/SFTP keluar |
| `com.apple.security.files.user-selected.read-write` | `true` | Dialog pilih/simpan berkas (SFTP, backup) |

App Sandbox mati berarti app **tidak bisa** masuk Mac App Store. Distribusi di
luar App Store (ad-hoc atau Developer ID) tidak mensyaratkan sandbox.

## Ikon aplikasi

`macos/Runner/Assets.xcassets/AppIcon.appiconset/` berisi ikon brand (pelat
baja + glyph `>_` membara) dalam tujuh ukuran, 16–1024 px. Untuk menggantinya,
timpa `app_icon_1024.png` lalu turunkan ukuran lain:

```bash
cd macos/Runner/Assets.xcassets/AppIcon.appiconset
for s in 512 256 128 64 32 16; do
  sips -z $s $s app_icon_1024.png --out app_icon_$s.png
done
```

macOS menyimpan ikon dalam cache. Kalau Dock masih menampilkan ikon lama
setelah build baru, jalankan `killall Dock`.

## Linux dan Windows

CI menghasilkan `HegiKetok-linux-x64.tar.gz` dan `HegiKetok-windows-x64.zip`.
Keduanya belum punya installer, dan updater dalam app baru mengunduh paket
macOS — di platform lain ia mengarahkan ke halaman rilis.

## Naik ke Developer ID (distribusi publik)

Bila nanti ingin app terbuka di Mac siapa pun tanpa peringatan, yang berubah
hanya tanda tangannya. Butuh keanggotaan Apple Developer Program (berbayar).

1. Buat sertifikat **Developer ID Application** di akun Apple Developer dan
   pasang di Keychain.
2. Simpan kredensial notarisasi sekali (disimpan di Keychain, bukan di repo):

   ```bash
   xcrun notarytool store-credentials "hegiketok-notary" \
     --apple-id "…" --team-id "…" --password "app-specific-password"
   ```

3. Jalankan skrip yang sama dengan dua variabel:

   ```bash
   SIGN_IDENTITY="Developer ID Application: NAMA (TEAMID)" \
   NOTARY_PROFILE="hegiketok-notary" \
   ./scripts/release_macos.sh
   ```

Skrip lalu menandatangani dengan hardened runtime dan timestamp, mengirim
`.dmg` ke notarisasi Apple, dan men-staple tiketnya. Jalur ini **belum pernah
dijalankan** (belum ada sertifikat). Hardened runtime bisa menuntut entitlement
tambahan; uji app hasilnya — terutama terminal lokal — sebelum merilis.
