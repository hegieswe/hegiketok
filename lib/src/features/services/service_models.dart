/// Satu unit service systemd.
class SystemdService {
  SystemdService({
    required this.unit,
    required this.load,
    required this.active,
    required this.sub,
    required this.description,
    this.enabledState,
  });

  final String unit; // mis. nginx.service
  final String load; // loaded, not-found, masked
  final String active; // active, inactive, failed, activating
  final String sub; // running, exited, dead, failed
  final String description;

  /// enabled, disabled, static, masked, generated, … (dari list-unit-files).
  String? enabledState;

  bool get isActive => active == 'active';
  bool get isFailed => active == 'failed' || sub == 'failed';
  bool get isRunning => isActive && (sub == 'running' || sub == 'exited');
  bool get isEnabled => enabledState == 'enabled' || enabledState == 'enabled-runtime';
  bool get canToggleEnable =>
      enabledState == 'enabled' ||
      enabledState == 'disabled' ||
      enabledState == 'enabled-runtime';

  /// Nama ringkas tanpa akhiran ".service".
  String get name =>
      unit.endsWith('.service') ? unit.substring(0, unit.length - 8) : unit;
}

/// Hasil pengambilan daftar service.
class ServiceSnapshot {
  const ServiceSnapshot({required this.services, this.error});

  final List<SystemdService> services;
  final String? error;
}
