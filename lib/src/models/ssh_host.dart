/// Metode autentikasi SSH yang didukung.
enum SshAuthMethod { password, key }

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
  });

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  /// Folder/kategori opsional untuk mengelompokkan host.
  final String? group;

  /// Id host tersimpan lain yang dipakai sebagai jump-host/bastion untuk
  /// menjangkau host ini. null = koneksi langsung.
  final String? jumpHostId;

  String get subtitle => '$username@$host:$port';

  SshHost copyWith({
    String? label,
    String? host,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
    String? group,
    String? jumpHostId,
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
