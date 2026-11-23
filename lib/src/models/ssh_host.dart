/// Metode autentikasi SSH yang didukung.
enum SshAuthMethod { password, key }

/// Sistem operasi host — menentukan ikon & warna identitas di daftar/grid.
/// [auto] = tebak dari label/host (perilaku lama).
enum HostOs {
  auto,
  linux,
  ubuntu,
  debian,
  fedora,
  centos,
  rhel,
  arch,
  alpine,
  raspberryPi,
  macos,
  windows,
  freebsd,
}

/// Representasi satu host SSH tersimpan.
///
/// PENTING: objek ini sengaja TIDAK menyimpan rahasia (password, private key,
/// passphrase). Metadata non-sensitif disimpan sebagai JSON biasa, sedangkan
/// rahasia disimpan terpisah di penyimpanan aman OS (Keychain) dan ditautkan
/// lewat [id]. Ini inti pendekatan local-first & aman kita.
class SshHost {
  const SshHost({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.authMethod = SshAuthMethod.password,
    this.group,
    this.jumpHostId,
    this.tags = const [],
    this.startupCommand,
    this.os = HostOs.auto,
    this.persistentSession = false,
    this.forwardAgent = false,
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  /// Folder/kategori opsional untuk mengelompokkan host.
  final String? group;

  /// Label bebas untuk mengkategorikan & memfilter host (mis. 'backend',
  /// 'dev', 'runner'). Non-sensitif, disimpan sebagai JSON biasa.
  final List<String> tags;

  /// Perintah yang dijalankan otomatis saat shell terbuka (startup snippet).
  final String? startupCommand;

  /// Id host tersimpan lain yang dipakai sebagai jump-host/bastion untuk
  /// menjangkau host ini. null = koneksi langsung.
  final String? jumpHostId;

  /// Sistem operasi (untuk ikon & warna). [HostOs.auto] = tebak dari nama.
  final HostOs os;

  /// Jaga sesi tetap hidup lewat tmux (ala tmux `new-session -A`). Saat aktif,
  /// shell dibungkus tmux di server; bila koneksi putus, program tetap jalan
  /// dan sambung-ulang otomatis MELANJUTKAN sesi yang sama. Butuh tmux di
  /// server (bila tidak ada → shell biasa, tanpa error).
  final bool persistentSession;

  /// Teruskan agen SSH (key host ini) ke server, sehingga dari server itu
  /// kamu bisa `ssh`/`git` ke mesin lain tanpa menyalin private key. Hanya
  /// berlaku untuk autentikasi key. Aktifkan hanya untuk server yang
  /// dipercaya: admin server itu bisa memakai agen selama sesi berlangsung.
  final bool forwardAgent;

  String get subtitle =>
      username.isEmpty ? '$host:$port' : '$username@$host:$port';

  SshHost copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
    String? group,
    String? jumpHostId,
    List<String>? tags,
    String? startupCommand,
    HostOs? os,
    bool? persistentSession,
    bool? forwardAgent,
    bool clearJumpHost = false,
  }) {
    return SshHost(
      id: id,
      label: label ?? this.label,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      group: group ?? this.group,
      jumpHostId: clearJumpHost ? null : (jumpHostId ?? this.jumpHostId),
      tags: tags ?? this.tags,
      startupCommand: startupCommand ?? this.startupCommand,
      os: os ?? this.os,
      persistentSession: persistentSession ?? this.persistentSession,
      forwardAgent: forwardAgent ?? this.forwardAgent,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'group': group,
        'jumpHostId': jumpHostId,
        'tags': tags,
        'startupCommand': startupCommand,
        'os': os.name,
        'persistentSession': persistentSession,
        'forwardAgent': forwardAgent,
      };

  factory SshHost.fromJson(Map<String, dynamic> json) {
    return SshHost(
      id: json['id'] as String,
      label: json['label'] as String,
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String,
      authMethod: SshAuthMethod.values.firstWhere(
        (m) => m.name == json['authMethod'],
        orElse: () => SshAuthMethod.password,
      ),
      group: json['group'] as String?,
      jumpHostId: json['jumpHostId'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      startupCommand: json['startupCommand'] as String?,
      os: HostOs.values.firstWhere(
        (o) => o.name == json['os'],
        orElse: () => HostOs.auto,
      ),
      persistentSession: json['persistentSession'] as bool? ?? false,
      forwardAgent: json['forwardAgent'] as bool? ?? false,
    );
  }
}

/// Rahasia untuk sebuah host, dibaca dari penyimpanan aman saat dibutuhkan.
class HostSecret {
  const HostSecret({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;
}
