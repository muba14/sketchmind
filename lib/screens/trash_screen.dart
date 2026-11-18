import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';

/// Silinen notlar 30 gün burada bekler, sonra kendiliğinden silinir.
class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final items = store.trash;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Çöp kutusu'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Çöp kutusu boşaltılsın mı?',
                    message: '${items.length} not kalıcı olarak silinecek. Bu geri alınamaz.');
                if (ok) await store.emptyTrash();
              },
              child: const Text('Boşalt', style: TextStyle(color: AppColors.separator)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Silinen notlar ${kTrashRetention.inDays} gün sonra kalıcı olarak silinir. '
              'Geri yüklemek için nota dokun.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 56, color: AppColors.muted),
                        SizedBox(height: 8),
                        Text('Çöp kutusu boş', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final days = n.daysLeftInTrash;
                      return ListTile(
                        leading: Icon(
                          n.type == NoteType.sketch ? Icons.draw_rounded : Icons.description_outlined,
                          color: AppColors.muted,
                        ),
                        title: Text(n.displayTitle),
                        subtitle: Text(
                          days <= 1 ? 'Yarın kalıcı olarak silinecek' : '$days gün kaldı',
                          style: TextStyle(
                            color: days <= 3 ? AppColors.separator : AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Geri yükle',
                          icon: const Icon(Icons.restore_rounded, color: AppColors.accentSoft),
                          onPressed: () => _restore(context, store, n),
                        ),
                        onTap: () => _actions(context, store, n),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _restore(BuildContext context, NoteStore store, Note n) {
    store.restore(n);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${n.displayTitle}" geri yüklendi')),
    );
  }

  Future<void> _actions(BuildContext context, NoteStore store, Note n) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(n.displayTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('Geri yükle'),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: AppColors.separator),
              title: const Text('Kalıcı olarak sil', style: TextStyle(color: AppColors.separator)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'restore') _restore(context, store, n);
    if (action == 'delete') {
      final ok = await confirm(context,
          title: 'Kalıcı olarak silinsin mi?', message: 'Bu not bir daha geri getirilemez.');
      if (ok) await store.deleteForever(n);
    }
  }
}
