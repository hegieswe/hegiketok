import 'package:material_ui/material_ui.dart';

import '../../models/ssh_host.dart';

/// Metadata tampilan per sistem operasi: nama, ikon, dan warna identitas.
/// Tanpa aset logo eksternal — ikon Material + warna merek sebagai pembeda.
extension HostOsInfo on HostOs {
  String get label => switch (this) {
        HostOs.auto => 'Deteksi otomatis',
        HostOs.linux => 'Linux',
        HostOs.ubuntu => 'Ubuntu',
        HostOs.debian => 'Debian',
        HostOs.fedora => 'Fedora',
        HostOs.centos => 'CentOS',
        HostOs.rhel => 'Red Hat',
        HostOs.arch => 'Arch',
        HostOs.alpine => 'Alpine',
        HostOs.raspberryPi => 'Raspberry Pi',
        HostOs.macos => 'macOS',
        HostOs.windows => 'Windows',
        HostOs.freebsd => 'FreeBSD',
      };

  IconData get icon => switch (this) {
        HostOs.macos => Icons.laptop_mac,
        HostOs.windows => Icons.window,
        HostOs.raspberryPi => Icons.memory_rounded,
        HostOs.freebsd => Icons.dns_rounded,
        HostOs.auto => Icons.dns_rounded,
        // Keluarga Linux berbagi glyph terminal, dibedakan oleh warna.
        _ => Icons.terminal_rounded,
      };

  /// Warna merek (best-effort) untuk ikon & tint latar avatar.
  Color get color => switch (this) {
        HostOs.ubuntu => const Color(0xFFE95420),
        HostOs.debian => const Color(0xFFD70A53),
        HostOs.fedora => const Color(0xFF51A2DA),
        HostOs.centos => const Color(0xFF932279),
        HostOs.rhel => const Color(0xFFEE0000),
        HostOs.arch => const Color(0xFF1793D1),
        HostOs.alpine => const Color(0xFF0D597F),
        HostOs.raspberryPi => const Color(0xFFC51A4A),
        HostOs.macos => const Color(0xFF8E8E93),
        HostOs.windows => const Color(0xFF0078D4),
        HostOs.freebsd => const Color(0xFFAB2B28),
        HostOs.linux => const Color(0xFFF5A623),
        HostOs.auto => const Color(0xFF6E79F2),
      };
}

/// Resolusi OS efektif: pakai [SshHost.os] bila dipilih, selain itu tebak dari
/// label & host (heuristik — perilaku lama dipertahankan).
HostOs resolveHostOs(SshHost host) {
  if (host.os != HostOs.auto) return host.os;
  final t = '${host.label} ${host.host}'.toLowerCase();
  bool has(String s) => t.contains(s);
  if (has('ubuntu')) return HostOs.ubuntu;
  if (has('debian')) return HostOs.debian;
  if (has('fedora')) return HostOs.fedora;
  if (has('centos')) return HostOs.centos;
  if (has('rhel') || has('red hat') || has('redhat')) return HostOs.rhel;
  if (has('arch')) return HostOs.arch;
  if (has('alpine')) return HostOs.alpine;
  if (has('raspberry') || has('rpi') || has('rasp')) return HostOs.raspberryPi;
  if (has('freebsd') || has('bsd')) return HostOs.freebsd;
  if (has('mac') || has('darwin') || has('osx')) return HostOs.macos;
  if (has('win')) return HostOs.windows;
  if (has('linux')) return HostOs.linux;
  // Default server paling umum.
  return HostOs.linux;
}

/// Ikon OS untuk sebuah host (dipakai avatar daftar/grid/palette).
IconData hostOsIcon(SshHost host) => resolveHostOs(host).icon;

/// Warna identitas OS untuk sebuah host.
Color hostOsColor(SshHost host) => resolveHostOs(host).color;
