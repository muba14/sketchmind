import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/media_cache.dart';

import '../models/note.dart';
import '../theme.dart';
import 'markdown_view.dart';
import 'sketch_painter.dart';

/// Notun küçük önizlemesi (el yazısı için sayfa resmi, metin için okuma görünümü).
class NotePreview extends StatelessWidget {
  const NotePreview({super.key, required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    if (note.locked) {
      return Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 36, color: AppColors.accentSoft),
            SizedBox(height: 6),
            Text('Kilitli', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );
    }
    if (note.type == NoteType.sketch) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 300,
            height: 300 * kPageHeight / kPageWidth,
            child: CustomPaint(
              painter: SketchPainter(
                strokes: note.strokes,
                images: note.images,
                media: context.read<MediaCache>(),
                paper: note.paper,
                paperColor: Color(note.paperColor),
                pages: 1,
                version: note.updated.microsecondsSinceEpoch,
              ),
            ),
          ),
        ),
      );
    }
    final src = note.content.length > 900 ? note.content.substring(0, 900) : note.content;
    return ClipRect(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: IgnorePointer(
            child: src.trim().isEmpty
                ? const Text('Boş not', style: TextStyle(color: AppColors.muted, fontSize: 11))
                : MarkdownView(source: src, scale: 0.6, interactive: false),
          ),
        ),
      ),
    );
  }
}

/// Squid'deki "Son Notlar" kartı: üstte önizleme, altta başlık + tarih şeridi.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NotePreview(note: note),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleFavorite,
                      icon: Icon(
                        note.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: note.favorite ? AppColors.star : AppColors.muted,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: AppColors.cardBar,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (note.pinned) ...[
                        const Icon(Icons.push_pin, size: 14, color: AppColors.accentSoft),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        note.type == NoteType.sketch ? Icons.draw_rounded : Icons.notes_rounded,
                        size: 14,
                        color: AppColors.accentSoft,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.white,
                            fontStyle: note.isUntitled ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note.folder.isEmpty
                        ? formatDate(note.updated)
                        : '${formatDate(note.updated)} · ${note.folder}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
