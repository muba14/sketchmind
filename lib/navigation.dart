import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/note_store.dart';
import 'models/note.dart';
import 'screens/sketch_note_screen.dart';
import 'security/lock.dart';
import 'screens/text_note_screen.dart';
import 'theme.dart';

/// Notu sekme olarak açar ve düzenleyiciye gider. Kilitliyse önce doğrulama ister.
Future<void> openNote(BuildContext context, Note note, {bool edit = false}) async {
  final store = context.read<NoteStore>();
  if (note.locked && !store.sessionUnlocked) {
    if (!await ensureUnlocked(context)) return;
    if (!context.mounted) return;
  }
  store.openTab(note.id);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => note.type == NoteType.text
        ? TextNoteScreen(noteId: note.id, startEditing: edit)
        : SketchNoteScreen(noteId: note.id),
  ));
}

/// `[[Başlık]]` bağlantısına dokunulunca: varsa açar, yoksa oluşturur.
Future<void> openOrCreateByTitle(BuildContext context, String title) {
  final store = context.read<NoteStore>();
  final existing = store.byTitle(title);
  if (existing != null) return openNote(context, existing);
  final created = store.createText(title: title.trim(), content: '');
  return openNote(context, created, edit: true);
}

Future<void> showNewNoteSheet(BuildContext context, {String folder = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: _NewNoteOption(
                icon: Icons.notes_rounded,
                title: 'Metin notu',
                subtitle: 'Markdown, [[bağlantı]], görevler',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final n = context.read<NoteStore>().createText(folder: folder);
                  openNote(context, n, edit: true);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NewNoteOption(
                icon: Icons.draw_rounded,
                title: 'El yazısı',
                subtitle: 'Kalem, fosforlu, silgi',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  final n = context.read<NoteStore>().createSketch(folder: folder);
                  openNote(context, n);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NewNoteOption extends StatelessWidget {
  const _NewNoteOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accentSoft),
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Not için uzun basma menüsü. Not silindiyse `true` döner.
Future<bool> showNoteActions(BuildContext context, Note note) async {
  final store = context.read<NoteStore>();
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note.displayTitle,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          _action(ctx, 'fav', note.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              note.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle'),
          _action(ctx, 'pin', note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              note.pinned ? 'Sabitlemeyi kaldır' : 'Üste sabitle'),
          _action(ctx, 'rename', Icons.edit_outlined, 'Yeniden adlandır'),
          _action(ctx, 'folder', Icons.folder_outlined,
              note.folder.isEmpty ? 'Klasöre taşı' : 'Klasör: ${note.folder}'),
          _action(ctx, 'lock', note.locked ? Icons.lock_open_outlined : Icons.lock_outline,
              note.locked ? 'Kilidi kaldır' : 'Kilitle (PIN / parmak izi)'),
          _action(ctx, 'dup', Icons.copy_rounded, 'Çoğalt'),
          _action(ctx, 'delete', Icons.delete_outline, 'Çöp kutusuna taşı', danger: true),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return false;

  switch (action) {
    case 'fav':
      note.favorite = !note.favorite;
      store.update(note, touch: false);
    case 'pin':
      note.pinned = !note.pinned;
      store.update(note, touch: false);
    case 'rename':
      final name = await promptText(context,
          title: 'Yeniden adlandır', initial: note.title, hint: 'Not başlığı');
      if (name != null) {
        final old = note.title;
        note.title = name;
        store.update(note);
        store.renameLinks(old, name);
      }
    case 'folder':
      final folder = await pickFolder(context, current: note.folder);
      if (folder != null) {
        note.folder = folder;
        store.update(note, touch: false);
      }
    case 'lock':
      await toggleLock(context, note);
    case 'dup':
      store.duplicate(note);
    case 'delete':
      store.moveToTrash(note);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('"${note.displayTitle}" çöp kutusuna taşındı'),
        action: SnackBarAction(label: 'Geri al', onPressed: () => store.restore(note)),
      ));
      return true;
  }
  return false;
}

Widget _action(BuildContext ctx, String value, IconData icon, String label,
    {bool danger = false}) {
  final color = danger ? AppColors.separator : AppColors.text;
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: TextStyle(color: color)),
    onTap: () => Navigator.pop(ctx, value),
  );
}

Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String hint = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.separator),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Klasör seçici. '' = klasör yok, null = vazgeçildi.
Future<String?> pickFolder(BuildContext context, {String current = ''}) async {
  final store = context.read<NoteStore>();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined, color: AppColors.accentSoft),
              title: const Text('Yeni klasör'),
              onTap: () => Navigator.pop(ctx, '\u0000new'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Klasör yok'),
              trailing: current.isEmpty ? const Icon(Icons.check, color: AppColors.accent) : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final f in store.folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f),
                trailing: f == current ? const Icon(Icons.check, color: AppColors.accent) : null,
                onTap: () => Navigator.pop(ctx, f),
              ),
          ],
        ),
      ),
    ),
  );
  if (result == '\u0000new') {
    if (!context.mounted) return null;
    final name = await promptText(context, title: 'Yeni klasör', hint: 'Klasör adı');
    if (name == null || name.isEmpty) return null;
    store.addFolder(name);
    return name;
  }
  return result;
}
