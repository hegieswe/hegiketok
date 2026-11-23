import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/snippet.dart';
import 'snippet_repository.dart';

final snippetRepositoryProvider =
    Provider<SnippetRepository>((ref) => SnippetRepository());

final snippetsProvider =
    AsyncNotifierProvider<SnippetsNotifier, List<Snippet>>(SnippetsNotifier.new);

class SnippetsNotifier extends AsyncNotifier<List<Snippet>> {
  SnippetRepository get _repo => ref.read(snippetRepositoryProvider);

  @override
  Future<List<Snippet>> build() => _repo.load();

  Future<void> save(Snippet snippet) async {
    await _repo.save(snippet);
    state = AsyncData(await _repo.load());
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    state = AsyncData(await _repo.load());
  }
}
