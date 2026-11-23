import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/snippet.dart';

/// Menyimpan & memuat pustaka snippet (perintah tersimpan) sebagai JSON biasa
/// di direktori dukungan aplikasi. Non-sensitif → transparan & mudah dibackup.
class SnippetRepository {
  SnippetRepository({Directory? directory}) : _dirOverride = directory;

  final Directory? _dirOverride;
  File? _cached;

  Future<File> _file() async {
    if (_cached != null) return _cached!;
    final dir = _dirOverride ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}/snippets.json');
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    _cached = file;
    return file;
  }

  Future<List<Snippet>> load() async {
    try {
      final content = await (await _file()).readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => Snippet.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Snippet> items) async {
    const encoder = JsonEncoder.withIndent('  ');
    await (await _file())
        .writeAsString(encoder.convert(items.map((e) => e.toJson()).toList()));
  }

  Future<void> save(Snippet snippet) async {
    final items = await load();
    final i = items.indexWhere((e) => e.id == snippet.id);
    if (i >= 0) {
      items[i] = snippet;
    } else {
      items.add(snippet);
    }
    await _write(items);
  }

  Future<void> delete(String id) async {
    final items = await load()
      ..removeWhere((e) => e.id == id);
    await _write(items);
  }
}
