import 'package:flutter/material.dart';

import '../data/media_cache.dart';
import '../models/note.dart';

/// Kağıt + kaydedilmiş çizgiler. Koordinatlar sayfa birimindedir
/// (genişlik [kPageWidth]); ekran boyutuna göre ölçeklenir.
class SketchPainter extends CustomPainter {
  SketchPainter({
    required this.strokes,
    required this.paper,
    required this.paperColor,
    required this.pages,
    this.images = const [],
    this.media,
    this.version = 0,
    this.showPageGaps = true,
  }) : super(repaint: media);

  final List<Stroke> strokes;
  final List<SketchImage> images;
  final MediaCache? media;
  final PaperType paper;
  final Color paperColor;
  final int pages;
  final int version;
  final bool showPageGaps;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / kPageWidth;
    canvas.save();
    canvas.scale(s);
    final h = size.height / s;
    canvas.clipRect(Rect.fromLTWH(0, 0, kPageWidth, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, kPageWidth, h), Paint()..color = paperColor);
    paintPaper(canvas, paper, paperColor, pages, h);
    if (showPageGaps && pages > 1) {
      final gap = Paint()
        ..color = const Color(0x55000000)
        ..strokeWidth = 8;
      for (var p = 1; p < pages; p++) {
        canvas.drawLine(Offset(0, p * kPageHeight), Offset(kPageWidth, p * kPageHeight), gap);
      }
    }
    for (final img in images) {
      drawSketchImage(canvas, img, media);
    }
    for (final st in strokes) {
      drawStroke(canvas, st);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SketchPainter old) =>
      old.version != version ||
      !identical(old.strokes, strokes) ||
      !identical(old.images, images) ||
      old.paper != paper ||
      old.paperColor != paperColor ||
      old.pages != pages;
}

/// Parmak/kalem hareket ederken çizilen tek çizgi (performans için ayrı katman).
class ActiveStrokePainter extends CustomPainter {
  ActiveStrokePainter(this.active) : super(repaint: active);
  final ValueNotifier<Stroke?> active;

  @override
  void paint(Canvas canvas, Size size) {
    final st = active.value;
    if (st == null) return;
    canvas.save();
    canvas.scale(size.width / kPageWidth);
    drawStroke(canvas, st);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ActiveStrokePainter old) => old.active != active;
}

void drawSketchImage(Canvas canvas, SketchImage img, MediaCache? media) {
  final image = media?.get(img.media);
  if (image == null) {
    canvas.drawRect(img.rect, Paint()..color = const Color(0x22888888));
    return;
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    img.rect,
    Paint()..filterQuality = FilterQuality.medium,
  );
}

void drawStroke(Canvas canvas, Stroke st) {
  if (st.points.isEmpty) return;
  final color = Color(st.color);
  final paint = Paint()
    ..color = st.highlighter ? color.withValues(alpha: 0.35) : color
    ..strokeWidth = st.width
    ..strokeCap = st.highlighter ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  final pts = st.points;
  if (pts.length == 1) {
    canvas.drawCircle(pts.first, st.width / 2, paint..style = PaintingStyle.fill);
    return;
  }
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (st.shape) {
    // Düzeltilmiş şekil: köşeler keskin kalsın.
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
    return;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = (pts[i] + pts[i + 1]) / 2;
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  canvas.drawPath(path, paint);
}

bool isDarkPaper(Color c) => c.computeLuminance() < 0.4;

void paintPaper(Canvas canvas, PaperType paper, Color paperColor, int pages, double height) {
  if (paper == PaperType.blank) return;
  final dark = isDarkPaper(paperColor);
  final line = Paint()
    ..color = dark ? const Color(0x26FFFFFF) : const Color(0x22000000)
    ..strokeWidth = 1.6;

  switch (paper) {
    case PaperType.blank:
      break;
    case PaperType.lined:
      final margin = Paint()
        ..color = const Color(0x66E5484D)
        ..strokeWidth = 2;
      for (var p = 0; p < pages; p++) {
        final top = p * kPageHeight;
        for (var y = top + 130.0; y < top + kPageHeight - 30; y += 50) {
          canvas.drawLine(Offset(0, y), Offset(kPageWidth, y), line);
        }
      }
      canvas.drawLine(const Offset(110, 0), Offset(110, height), margin);
      break;
    case PaperType.grid:
      for (var x = 40.0; x < kPageWidth; x += 40) {
        canvas.drawLine(Offset(x, 0), Offset(x, height), line);
      }
      for (var y = 40.0; y < height; y += 40) {
        canvas.drawLine(Offset(0, y), Offset(kPageWidth, y), line);
      }
      break;
    case PaperType.dotted:
      final dot = Paint()..color = dark ? const Color(0x55FFFFFF) : const Color(0x44000000);
      for (var y = 40.0; y < height; y += 40) {
        for (var x = 40.0; x < kPageWidth; x += 40) {
          canvas.drawCircle(Offset(x, y), 2.6, dot);
        }
      }
      break;
    case PaperType.cornell:
      final box = Paint()
        ..color = dark ? const Color(0x40FFFFFF) : const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      final labelColor = dark ? const Color(0x88FFFFFF) : const Color(0x88000000);
      for (var p = 0; p < pages; p++) {
        final t = p * kPageHeight;
        const pad = 14.0;
        const leftW = 300.0;
        const headH = 130.0;
        const sumH = 230.0;
        const r = Radius.circular(10);
        // Sol sütun: anahtar noktalar
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(pad, t + pad, leftW, kPageHeight - sumH - pad * 3), r),
          box,
        );
        // Sağ üst: ad/tarih/konu
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(pad * 2 + leftW, t + pad, kPageWidth - leftW - pad * 3, headH), r),
          box,
        );
        // Sağ: notlar
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(pad * 2 + leftW, t + pad * 2 + headH, kPageWidth - leftW - pad * 3,
                  kPageHeight - sumH - headH - pad * 4),
              r),
          box,
        );
        // Alt: özet
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(pad, t + kPageHeight - sumH - pad, kPageWidth - pad * 2, sumH), r),
          box,
        );
        _label(canvas, 'ANAHTAR NOKTALAR', Offset(pad + 16, t + pad + 12), labelColor);
        _label(canvas, 'AD / TARİH / KONU', Offset(pad * 2 + leftW + 16, t + pad + 12), labelColor);
        _label(canvas, 'NOTLAR', Offset(pad * 2 + leftW + 16, t + pad * 2 + headH + 12), labelColor);
        _label(canvas, 'ÖZET', Offset(pad + 16, t + kPageHeight - sumH - pad + 12), labelColor);
      }
      break;
  }
}

void _label(Canvas canvas, String text, Offset at, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 22, letterSpacing: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}
