import 'server_info.dart';

/// Satu peringatan ambang terlampaui.
class ServerAlert {
  const ServerAlert(this.label, this.value, this.threshold);

  final String label; // "CPU", "Memory", "Disk /var"
  final double value; // nilai aktual (persen)
  final double threshold; // ambang (persen)

  String get message =>
      '$label ${value.toStringAsFixed(0)}% '
      '(ambang ${threshold.toStringAsFixed(0)}%)';
}

/// Hitung peringatan dari snapshot server terhadap ambang yang ditetapkan.
/// Fungsi murni → mudah diuji tanpa server/UI.
List<ServerAlert> computeAlerts(
  ServerInfo info, {
  required double cpu,
  required double mem,
  required double disk,
}) {
  final alerts = <ServerAlert>[];
  if (info.cpuUsage >= cpu) {
    alerts.add(ServerAlert('CPU', info.cpuUsage, cpu));
  }
  if (info.memPercent >= mem) {
    alerts.add(ServerAlert('Memory', info.memPercent, mem));
  }
  for (final d in info.disks) {
    if (d.usePercent >= disk) {
      alerts.add(ServerAlert('Disk ${d.mount}', d.usePercent.toDouble(), disk));
    }
  }
  return alerts;
}
