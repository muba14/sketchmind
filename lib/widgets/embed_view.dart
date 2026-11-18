import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/media_cache.dart';
import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';
import 'markdown_view.dart';
import 'sketch_painter.dart';

/// Metin notunun içine `![[Başlık]]` ile gömülen not.
/// El yazısı notları küçük resim olarak, metin notları kısa önizleme olarak görünür.
class NoteEmbed extends StatelessWidget {
  const NoteEmbed({super.key, required this.target});
  final String target;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    final n = store.byTitle(target);

    if (n == null) {
      return _frame(
        onTap: () {
          final created = store.createSketch(title: target.trim());
          openNote(context, created);
        },
        child: _infoRow(Icons.add_circle_outline, '"$target" henüz yok',
            'Dokun, bu adla bir çizim sayfası oluştur', AppColors.missingLink),
      );
    }
    if (n.locked && !store.sessionUnlocked) {
      return _frame(
        onTap: () => openNote(context, n),
        child: _infoRow(Icons.lock_rounded, n.displayTitle, 'Kilitli not', AppColors.accentSoft),
      );
    }
    if (n.type == NoteType.text) {
      final src = n.content.length > 600 ? n.content.substring(0, 600) : n.content;
      return _frame(
        onTap: () => openNote(context, n),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(Icons.description_outlined, n.displayTitle),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: IgnorePointer(
                      child: MarkdownView(source: src, scale: 0.9, interactive: false),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // El yazısı: ilk sayfanın dolu kısmını göster.
    final media = context.read<MediaCache>();
    var bottom = 0.0;
    for (final s in n.strokes) {
      final b = s.bounds;
      if (b.top < kPageHeight) bottom = max(bottom, b.bottom);
    }
    for (final im in n.images) {
      if (im.rect.top < kPageHeight) bottom = max(bottom, im.rect.bottom);
    }
    final visible = (bottom + 60).clamp(380.0, kPageHeight).toDouble();

    return _frame(
      onTap: () => openNote(context, n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final fullH = w * kPageHeight / kPageWidth;
            return SizedBox(
              height: w * visible / kPageWidth,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: fullH,
                  maxHeight: fullH,
                  child: CustomPaint(
                    size: Size(w, fullH),
                    painter: SketchPainter(
                      strokes: n.strokes,
                      images: n.images,
                      media: media,
                      paper: n.paper,
                      paperColor: Color(n.paperColor),
                      pages: 1,
                      version: n.updated.microsecondsSinceEpoch,
                    ),
                  ),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: _title(Icons.draw_rounded, n.displayTitle)),
                if (n.pages > 1)
                  Text('${n.pages} sayfa  ',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame({required Widget child, required VoidCallback onTap}) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          ),
        ),
      );

  Widget _title(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.accentSoft),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ],
      );

  Widget _infoRow(IconData icon, String title, String sub, Color color) => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}
