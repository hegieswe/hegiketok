/// Satu container Docker (metadata + stats opsional bila sedang berjalan).
class DockerContainer {
  DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.ports,
    this.cpuPerc,
    this.memUsage,
    this.memPerc,
    this.netIO,
    this.blockIO,
  });

  final String id;
  final String name;
  final String image;
  final String state; // running, exited, created, paused, restarting
  final String status; // mis. "Up 2 hours"
  final String ports;

  // Stats (hanya untuk container yang berjalan)
  double? cpuPerc;
  String? memUsage;
  double? memPerc;
  String? netIO;
  String? blockIO;

  bool get isRunning => state == 'running';
  String get shortId => id.length > 12 ? id.substring(0, 12) : id;
}

/// Hasil pengambilan daftar container + versi daemon.
class DockerSnapshot {
  const DockerSnapshot({
    required this.containers,
    required this.serverVersion,
    this.error,
  });

  final List<DockerContainer> containers;
  final String serverVersion;
  final String? error;
}
