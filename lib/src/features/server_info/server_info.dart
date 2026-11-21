/// Satu entri disk/mount.
class DiskInfo {
  const DiskInfo({
    required this.filesystem,
    required this.mount,
    required this.sizeKb,
    required this.usedKb,
    required this.availKb,
    required this.usePercent,
  });

  final String filesystem;
  final String mount;
  final int sizeKb;
  final int usedKb;
  final int availKb;
  final int usePercent;
}

/// Satu interface jaringan + alamat IP.
class NetInterface {
  const NetInterface(this.name, this.address);
  final String name;
  final String address;
}

/// Satu proses yang sedang berjalan.
class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.command,
  });

  final int pid;
  final String user;
  final double cpu; // %CPU
  final double mem; // %MEM
  final String command;
}

/// Rincian pemakaian CPU (persentase dari total).
class CpuBreakdown {
  const CpuBreakdown({
    this.user = 0,
    this.system = 0,
    this.nice = 0,
    this.iowait = 0,
    this.steal = 0,
    this.idle = 0,
  });

  final double user;
  final double system;
  final double nice;
  final double iowait;
  final double steal;
  final double idle;
}

/// Snapshot informasi sistem sebuah server (hasil dikumpulkan via SSH).
class ServerInfo {
  const ServerInfo({
    required this.hostname,
    required this.os,
    required this.kernel,
    required this.uptime,
    required this.cpuModel,
    required this.cpuCores,
    required this.loadAvg,
    required this.cpuUsage,
    required this.perCore,
    required this.cpuBreakdown,
    required this.cpuTemp,
    required this.memTotalKb,
    required this.memUsedKb,
    required this.memCacheKb,
    required this.memFreeKb,
    required this.swapTotalKb,
    required this.swapUsedKb,
    required this.disks,
    required this.networks,
    required this.usersLoggedIn,
    required this.processes,
    required this.topProcesses,
    required this.collectedAt,
  });

  final String hostname;
  final String os;
  final String kernel;
  final String uptime;
  final String cpuModel;
  final int cpuCores;
  final List<double> loadAvg;
  final double cpuUsage; // persen 0..100 (agregat)
  final List<double> perCore; // %CPU tiap core
  final CpuBreakdown cpuBreakdown;
  final double? cpuTemp; // Celsius, null bila tak tersedia
  final int memTotalKb;
  final int memUsedKb; // RAM terpakai nyata (tanpa cache)
  final int memCacheKb; // buffers + cache (bisa direклaim)
  final int memFreeKb;
  final int swapTotalKb;
  final int swapUsedKb;
  final List<DiskInfo> disks;
  final List<NetInterface> networks;
  final int usersLoggedIn;
  final int processes;
  final List<ProcessInfo> topProcesses;
  final DateTime collectedAt;

  double get memPercent =>
      memTotalKb == 0 ? 0 : (memUsedKb / memTotalKb * 100);
  double get cachePercent =>
      memTotalKb == 0 ? 0 : (memCacheKb / memTotalKb * 100);
  double get swapPercent =>
      swapTotalKb == 0 ? 0 : (swapUsedKb / swapTotalKb * 100);
}
