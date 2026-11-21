import 'package:material_ui/material_ui.dart';

/// Kontrak umum untuk satu tab di workspace — bisa berupa terminal (lokal/SSH)
/// maupun browser file SFTP. Workspace menampilkan daftar [WorkspaceTab] tanpa
/// perlu tahu jenis isinya.
abstract class WorkspaceTab {
  /// Label untuk tab.
  String get title;

  /// Ikon untuk tab.
  IconData get icon;

  /// Konten yang ditampilkan saat tab aktif.
  Widget build(BuildContext context);

  /// Lepaskan sumber daya (koneksi, proses) saat tab ditutup.
  void dispose();
}
