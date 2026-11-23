/// Perintah tersimpan yang bisa diselipkan/ dijalankan di terminal.
///
/// Non-sensitif (bukan rahasia) → disimpan sebagai JSON biasa, mudah
/// di-backup/ekspor. Sejalan dengan prinsip local-first.
class Snippet {
  const Snippet({
    required this.id,
    required this.name,
    required this.command,
    this.description,
  });

  final String id;
  final String name;
  final String command;
  final String? description;

  Snippet copyWith({String? name, String? command, String? description}) {
    return Snippet(
      id: id,
      name: name ?? this.name,
      command: command ?? this.command,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'description': description,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        id: json['id'] as String,
        name: json['name'] as String,
        command: json['command'] as String,
        description: json['description'] as String?,
      );
}
