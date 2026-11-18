import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';
import '../security/lock.dart';
import '../widgets/embed_view.dart';
import '../widgets/markdown_view.dart';
import 'home_screen.dart';

/// Obsidian tarzı metin notu: okuma modu (canlı görünüm) ve yazma modu.
class TextNoteScreen extends StatefulWidget {
  const TextNoteScreen({super.key, required this.noteId, this.startEditing = false});

  final String noteId;
  final bool startEditing;

  @override
  State<TextNoteScreen> createState() => _TextNoteScreenState();
}

class _TextNoteScreenState extends State<TextNoteScreen> {
  late final NoteStore _store;
  Note? _note;
  late bool _editing;
  late final TextEditingController _title;
  late final TextEditingController _body;
  final _bodyFocus = FocusNode();
  late String _originalTitle;
  List<String> _suggestions = const [];

  static final _openLink = RegExp(r'\[\[([^\]\n]*)$');

  @override
  void initState() {
    super.initState();
    _store = context.read<NoteStore>();
    _note = _store.byId(widget.noteId);
    _editing = widget.startEditing;
    _title = TextEditingController(text: _note?.title ?? '');
    _body = TextEditingController(text: _note?.content ?? '');
    _originalTitle = _note?.title ?? '';
    _title.addListener(_onTitle);
    _body.addListener(_onBody);
  }

  void _onTitle() {
    final n = _note;
    if (n == null || n.title == _title.text) return;
    n.title = _title.text;
    _store.update(n);
  }

  void _onBody() {
    final n = _note;
    if (n == null) return;
    if (n.content != _body.text) {
      n.content = _body.text;
      _store.update(n);
    }
    _updateSuggestions();
  }

  /// `[[` yazılınca not başlığı önerileri.
  void _updateSuggestions() {
    final sel = _body.selection;
    List<String> next = const [];
    if (sel.isValid && sel.isCollapsed) {
      final before = _body.text.substring(0, sel.baseOffset);
      final m = _openLink.firstMatch(before);
      if (m != null) {
        final q = m.group(1)!.toLowerCase();
        next = _store.notes
            .where((n) => n.id != _note?.id && !n.isUntitled)
            .map((n) => n.title.trim())
            .where((t) => t.toLowerCase().contains(q))
            .take(8)
            .toList();
      }
    }
    if (next.join('\u0000') != _suggestions.join('\u0000')) {
      setState(() => _suggestions = next);
    }
  }

  void _applySuggestion(String title) {
    final sel = _body.selection;
    final text = _body.text;
    final before = text.substring(0, sel.baseOffset);
    final m = _openLink.firstMatch(before)!;
    final after = text.substring(sel.baseOffset);
    final closing = after.startsWith(']]') ? '' : ']]';
    final newBefore = '${before.substring(0, m.start)}[[$title$closing';
    _body.value = TextEditingValue(
      text: newBefore + after,
      selection: TextSelection.collapsed(
        offset: newBefore.length + (closing.isEmpty ? 2 : 0),
      ),
    );
  }

  void _commitRename() {
    final n = _note;
    if (n == null) return;
    if (_originalTitle.trim() != n.title.trim()) {
      _store.renameLinks(_originalTitle, n.title);
      _originalTitle = n.title;
    }
  }

  @override
  void dispose() {
    // Ağaç kilitliyken dinleyicileri tetiklememek için bir sonraki adımda yap.
    final n = _note;
    final old = _originalTitle;
    if (n != null && old.trim() != n.title.trim()) {
      final store = _store;
      final newTitle = n.title;
      Future.microtask(() => store.renameLinks(old, newTitle));
    }
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ düzenleme yardımcıları
  void _wrap(String left, [String? right]) {
    right ??= left;
    final sel = _body.selection;
    final text = _body.text;
    if (!sel.isValid) {
      _body.text = '$text$left$right';
      return;
    }
    final selected = sel.textInside(text);
    final replaced = '$left$selected$right';
    _body.value = TextEditingValue(
      text: sel.textBefore(text) + replaced + sel.textAfter(text),
      selection: selected.isEmpty
          ? TextSelection.collapsed(offset: sel.start + left.length)
          : TextSelection(
              baseOffset: sel.start + left.length,
              extentOffset: sel.start + left.length + selected.length,
            ),
    );
  }

  void _linePrefix(String prefix) {
    final sel = _body.selection;
    final text = _body.text;
    final pos = sel.isValid ? sel.start : text.length;
    final lineStart = pos == 0 ? 0 : text.lastIndexOf('\n', pos - 1) + 1;
    final line = text.substring(lineStart);
    if (line.startsWith(prefix)) {
      _body.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart + prefix.length, ''),
        selection: TextSelection.collapsed(offset: (pos - prefix.length).clamp(lineStart, text.length)),
      );
    } else {
      _body.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart, prefix),
        selection: TextSelection.collapsed(offset: pos + prefix.length),
      );
    }
  }

  void _insertBlock(String block) {
    final sel = _body.selection;
    final text = _body.text;
    final pos = sel.isValid ? sel.start : text.length;
    final needsNl = pos > 0 && text[pos - 1] != '\n';
    final insert = '${needsNl ? '\n' : ''}$block\n';
    _body.value = TextEditingValue(
      text: text.replaceRange(pos, sel.isValid ? sel.end : pos, insert),
      selection: TextSelection.collapsed(offset: pos + insert.length),
    );
  }

  /// Bir el yazısı sayfasını `![[Başlık]]` olarak gömer (ya da yenisini oluşturur).
  Future<void> _embedSketch() async {
    final sketches = _store.sorted(
        _store.notes.where((n) => n.type == NoteType.sketch && !n.isUntitled));
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Çizim göm',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: AppColors.accentSoft),
                title: const Text('Yeni çizim sayfası'),
                onTap: () => Navigator.pop(ctx, '\u0000new'),
              ),
              for (final n in sketches)
                ListTile(
                  leading: const Icon(Icons.draw_rounded),
                  title: Text(n.displayTitle),
                  subtitle: Text(formatDate(n.updated),
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  onTap: () => Navigator.pop(ctx, n.title.trim()),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    var title = picked;
    if (picked == '\u0000new') {
      final name = await promptText(context, title: 'Yeni çizim', hint: 'Ör. Türev grafiği');
      if (name == null || name.isEmpty) return;
      title = _store.titleExists(name) ? '$name (çizim)' : name;
      _store.createSketch(title: title, folder: _note?.folder ?? '');
    }
    _insertBlock('![[$title]]');
  }

  void _setEditing(bool v) {
    if (!v) {
      _commitRename();
      FocusScope.of(context).unfocus();
    }
    setState(() {
      _editing = v;
      _suggestions = const [];
    });
    if (v) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bodyFocus.requestFocus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final note = _note;
    if (note == null || store.byId(note.id) == null) {
      return const Scaffold(body: Center(child: Text('Not bulunamadı')));
    }
    if (note.locked && !store.sessionUnlocked) {
      return Scaffold(appBar: AppBar(), body: LockedView(note: note));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          note.folder.isEmpty ? 'Not' : note.folder,
          style: const TextStyle(fontSize: 15, color: AppColors.muted),
        ),
        actions: [
          IconButton(
            tooltip: note.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
            onPressed: () {
              note.favorite = !note.favorite;
              store.update(note, touch: false);
            },
            icon: Icon(
              note.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: note.favorite ? AppColors.star : null,
            ),
          ),
          IconButton(
            tooltip: _editing ? 'Okuma modu' : 'Düzenle',
            onPressed: () => _setEditing(!_editing),
            icon: Icon(_editing ? Icons.menu_book_rounded : Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Diğer',
            onPressed: () async {
              _commitRename();
              final deleted = await showNoteActions(context, note);
              if (!context.mounted) return;
              if (deleted) {
                Navigator.of(context).pop();
              } else if (_title.text != note.title) {
                _title.text = note.title;
                _originalTitle = note.title;
              }
            },
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: _editing ? _buildEditor(note) : _buildReader(store, note),
    );
  }

  // ------------------------------------------------------------ okuma modu
  Widget _buildReader(NoteStore store, Note note) {
    final backlinks = store.backlinks(note);
    final outgoing = note.links;
    final tags = note.tags.toList()..sort();

    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            note.displayTitle,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: note.isUntitled ? AppColors.muted : Colors.white,
              fontStyle: note.isUntitled ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Düzenlendi: ${formatDate(note.updated)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (note.content.trim().isEmpty)
            GestureDetector(
              onTap: () => _setEditing(true),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Bu not boş. Yazmaya başlamak için dokun ya da ✏️ simgesine bas.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          else
            MarkdownView(
              source: note.content,
              linkExists: store.titleExists,
              embedBuilder: (t) => NoteEmbed(target: t),
              onLinkTap: (t) => openOrCreateByTitle(context, t),
              onTagTap: (t) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FilteredNotesScreen(filter: NoteFilter.tag(t)),
              )),
              onChanged: (src) {
                // Kutu işaretlendi: denetleyici dinleyicisi notu günceller.
                _body.text = src;
              },
            ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tags)
                  ActionChip(
                    label: Text('#$t'),
                    labelStyle: const TextStyle(color: AppColors.tag, fontSize: 12),
                    backgroundColor: AppColors.tag.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FilteredNotesScreen(filter: NoteFilter.tag(t)),
                    )),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          _LinkSection(
            title: 'Geri bağlantılar',
            icon: Icons.call_received_rounded,
            empty: 'Bu nota henüz bağlanan not yok.',
            items: [
              for (final b in backlinks)
                _LinkItem(b.displayTitle, b.type, () => openNote(context, b)),
            ],
          ),
          const SizedBox(height: 12),
          _LinkSection(
            title: 'Giden bağlantılar',
            icon: Icons.call_made_rounded,
            empty: 'Bu not başka bir nota bağlanmıyor.',
            items: [
              for (final t in outgoing)
                _LinkItem(
                  t,
                  store.byTitle(t)?.type,
                  () => openOrCreateByTitle(context, t),
                ),
            ],
          ),
        ],
    );
  }

  // ------------------------------------------------------------ yazma modu
  Widget _buildEditor(Note note) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              TextField(
                controller: _title,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Başlık',
                  filled: false,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _bodyFocus.requestFocus(),
              ),
              TextField(
                controller: _body,
                focusNode: _bodyFocus,
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.text,
                ),
                decoration: const InputDecoration(
                  hintText: 'Yazmaya başla... [[bağlantı]], - [ ] görev, #etiket',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            height: 44,
            color: AppColors.card,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ActionChip(
                      avatar: const Icon(Icons.link, size: 16, color: AppColors.accentSoft),
                      label: Text(s),
                      onPressed: () => _applySuggestion(s),
                    ),
                  ),
              ],
            ),
          ),
        _EditorToolbar(
          onTask: () => _linePrefix('- [ ] '),
          onHeading: () => _linePrefix('## '),
          onBullet: () => _linePrefix('- '),
          onBold: () => _wrap('**'),
          onItalic: () => _wrap('*'),
          onStrike: () => _wrap('~~'),
          onHighlight: () => _wrap('=='),
          onCode: () => _wrap('`'),
          onLink: () => _wrap('[[', ']]'),
          onEmbed: _embedSketch,
          onTag: () => _wrap('#', ''),
          onRule: () => _insertBlock('----------------------------------------'),
          onQuote: () => _linePrefix('> '),
        ),
      ],
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.onTask,
    required this.onHeading,
    required this.onBullet,
    required this.onBold,
    required this.onItalic,
    required this.onStrike,
    required this.onHighlight,
    required this.onCode,
    required this.onLink,
    required this.onEmbed,
    required this.onTag,
    required this.onRule,
    required this.onQuote,
  });

  final VoidCallback onTask, onHeading, onBullet, onBold, onItalic, onStrike;
  final VoidCallback onHighlight, onCode, onLink, onEmbed, onTag, onRule, onQuote;

  @override
  Widget build(BuildContext context) {
    Widget b(IconData icon, String tip, VoidCallback f) => IconButton(
          tooltip: tip,
          onPressed: f,
          icon: Icon(icon, size: 22),
          color: AppColors.text,
        );
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              b(Icons.check_circle_outline, 'Görev', onTask),
              b(Icons.title, 'Başlık', onHeading),
              b(Icons.format_list_bulleted, 'Liste', onBullet),
              b(Icons.link, '[[Bağlantı]]', onLink),
              b(Icons.draw_outlined, 'Çizim göm ![[ ]]', onEmbed),
              b(Icons.format_bold, 'Kalın', onBold),
              b(Icons.format_italic, 'İtalik', onItalic),
              b(Icons.format_strikethrough, 'Çizili', onStrike),
              b(Icons.highlight, 'Vurgu', onHighlight),
              b(Icons.code, 'Kod', onCode),
              b(Icons.tag, 'Etiket', onTag),
              b(Icons.format_quote, 'Alıntı', onQuote),
              b(Icons.horizontal_rule, 'Ayırıcı', onRule),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkItem {
  const _LinkItem(this.title, this.type, this.onTap);
  final String title;
  final NoteType? type;
  final VoidCallback onTap;
}

class _LinkSection extends StatelessWidget {
  const _LinkSection({
    required this.title,
    required this.icon,
    required this.empty,
    required this.items,
  });

  final String title;
  final IconData icon;
  final String empty;
  final List<_LinkItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Text('$title (${items.length})',
                    style: const TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(empty, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          for (final it in items)
            ListTile(
              dense: true,
              leading: Icon(
                it.type == null
                    ? Icons.add_circle_outline
                    : it.type == NoteType.sketch
                        ? Icons.draw_rounded
                        : Icons.description_outlined,
                size: 20,
                color: it.type == null ? AppColors.missingLink : AppColors.accentSoft,
              ),
              title: Text(
                it.title,
                style: TextStyle(
                  color: it.type == null ? AppColors.missingLink : AppColors.text,
                ),
              ),
              subtitle: it.type == null
                  ? const Text('Henüz yok — dokununca oluşturulur',
                      style: TextStyle(fontSize: 11, color: AppColors.muted))
                  : null,
              onTap: it.onTap,
            ),
        ],
      ),
    );
  }
}
