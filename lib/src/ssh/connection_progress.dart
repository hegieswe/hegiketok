import 'package:material_ui/material_ui.dart';

/// Status satu langkah handshake.
enum StepStatus { active, done, failed }

/// Satu langkah dalam proses koneksi SSH (dipakai "handshake stepper").
class HandshakeStep {
  HandshakeStep(this.label, {this.status = StepStatus.active, this.detail});

  final String label;
  StepStatus status;
  String? detail;
}

/// State progres koneksi yang dapat dipantau UI. Dipakai bersama oleh terminal,
/// SFTP, info server, dan Docker agar semuanya menampilkan tahapan yang sama
/// (resolusi, TCP, autentikasi, tunnel bastion, buka channel).
class ConnectionProgress extends ChangeNotifier {
  final List<HandshakeStep> steps = [];
  bool finished = false;
  String? error;

  /// Tambah langkah baru (status aktif) dan kembalikan referensinya.
  HandshakeStep begin(String label) {
    final step = HandshakeStep(label);
    steps.add(step);
    notifyListeners();
    return step;
  }

  /// Tandai sebuah langkah selesai.
  void complete(HandshakeStep step, {String? detail}) {
    step.status = StepStatus.done;
    if (detail != null) step.detail = detail;
    notifyListeners();
  }

  /// Tandai langkah gagal + simpan pesan error keseluruhan.
  void fail(HandshakeStep step, String message) {
    step.status = StepStatus.failed;
    step.detail = message;
    error = message;
    notifyListeners();
  }

  /// Semua langkah selesai — koneksi siap.
  void finish() {
    finished = true;
    notifyListeners();
  }

  /// Ulangi dari awal (mis. tombol "coba lagi").
  void reset() {
    steps.clear();
    finished = false;
    error = null;
    notifyListeners();
  }
}
