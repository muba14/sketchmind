import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';

/// Başlık ve içerikte tam metin arama.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final results = store.search(_q);

    return Scaffold(
      appBar: AppBar(title: const Text('Ara')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _ctrl,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Notlarda ara…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _q.trim().isEmpty
                ? const Center(
                    child: Text('Başlık, metin ya da #etiket ara',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : results.isEmpty
                    ? const Center(
                        child: Text('Sonuç yok', style: TextStyle(color: AppColors.muted)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, i) {
                          final n = results[i];
                          return ListTile(
                            leading: Icon(
                              n.type == NoteType.sketch
                                  ? Icons.draw_rounded
                                  : Icons.description_outlined,
                              color: AppColors.accentSoft,
                            ),
                            title: _highlight(n.displayTitle, _q,
                                const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: n.type == NoteType.text
                                ? _highlight(_snippet(n.content, _q), _q,
                                    const TextStyle(color: AppColors.muted, fontSize: 13))
                                : Text('El yazısı · ${formatDate(n.updated)}',
                                    style: const TextStyle(color: AppColors.muted)),
                            onTap: () => openNote(context, n),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  static String _snippet(String content, String q) {
    final flat = content.replaceAll('\n', ' ');
    final i = flat.toLowerCase().indexOf(q.trim().toLowerCase());
    if (i < 0) return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
    final start = (i - 40).clamp(0, flat.length);
    final end = (i + 80).clamp(0, flat.length);
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  static Widget _highlight(String text, String q, TextStyle style) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return Text(text, style: style, maxLines: 2);
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var last = 0;
    while (true) {
      final i = lower.indexOf(query, last);
      if (i < 0 || lower.length != text.length) break;
      if (i > last) spans.add(TextSpan(text: text.substring(last, i)));
      spans.add(TextSpan(
        text: text.substring(i, i + query.length),
        style: const TextStyle(
          backgroundColor: AppColors.highlight,
          color: AppColors.highlightText,
        ),
      ));
      last = i + query.length;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
