import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme.dart';

/// Obsidian'daki "okuma modu" gibi canlı Markdown görünümü.
///
/// Desteklenenler: başlıklar, yapılacak kutuları (dokununca işaretlenir),
/// madde/numaralı listeler, alıntı, kod bloğu, ayırıcı çizgi,
/// "Başlık ------" tarzı renkli ayırıcılar, **kalın**, *italik*, ~~çizili~~,
/// ==vurgu==, `kod`, [[bağlantı]] ve #etiket.
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.source,
    this.scale = 1,
    this.interactive = true,
    this.onChanged,
    this.onLinkTap,
    this.onTagTap,
    this.linkExists,
    this.embedBuilder,
  });

  final String source;
  final double scale;
  final bool interactive;

  /// Bir kutu işaretlenince güncellenmiş metni verir.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onLinkTap;
  final ValueChanged<String>? onTagTap;
  final bool Function(String title)? linkExists;

  /// `![[Not]]` satırları için gömülü görünüm (çizim küçük resmi vb.).
  final Widget Function(String target)? embedBuilder;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final List<TapGestureRecognizer> _recognizers = [];

  static final _codeFence = RegExp(r'^\s*```');
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _task = RegExp(r'^(\s*)[-*+] \[( |x|X)\]\s?(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _quote = RegExp(r'^\s*>\s?(.*)$');
  static final _rule = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
  static final _labeledRule = RegExp(r'^(.*\S)\s*-{5,}\s*$');
  static final _inline = RegExp(
    r'(\*\*(.+?)\*\*)|(~~(.+?)~~)|(==(.+?)==)|(`([^`]+)`)|(\[\[([^\]]+)\]\])|(\*(?!\s)([^*]+?)\*)|((?<=^|\s)#[\p{L}_][\p{L}\p{N}_/-]*)',
    unicode: true,
  );

  double get s => widget.scale;

  TextStyle get _base => TextStyle(
        color: AppColors.text,
        fontSize: 15 * s,
        height: 1.45,
      );

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  TapGestureRecognizer? _tap(VoidCallback cb) {
    if (!widget.interactive) return null;
    final r = TapGestureRecognizer()..onTap = cb;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final lines = widget.source.split('\n');
    final children = <Widget>[];
    var i = 0;
    var blankRun = 0;

    while (i < lines.length) {
      final line = lines[i];

      // Kod bloğu
      if (_codeFence.hasMatch(line)) {
        final buf = <String>[];
        i++;
        while (i < lines.length && !_codeFence.hasMatch(lines[i])) {
          buf.add(lines[i]);
          i++;
        }
        i++; // kapanış
        children.add(_codeBlock(buf.join('\n')));
        blankRun = 0;
        continue;
      }

      if (line.trim().isEmpty) {
        blankRun++;
        if (blankRun <= 2) children.add(SizedBox(height: 8 * s));
        i++;
        continue;
      }
      blankRun = 0;

      final idx = i;
      Match? m;
      final embed = embedLineRegex.firstMatch(line);
      if (embed != null) {
        final target = embed.group(1)!.trim();
        final builder = widget.embedBuilder;
        children.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 6 * s),
          child: builder != null ? builder(target) : _embedPlaceholder(target),
        ));
        i++;
        continue;
      }
      if (_rule.hasMatch(line)) {
        children.add(_divider());
      } else if ((m = _heading.firstMatch(line)) != null) {
        children.add(_headingWidget(m!.group(1)!.length, m.group(2)!));
      } else if ((m = _task.firstMatch(line)) != null) {
        children.add(_taskWidget(lines, idx, m!));
      } else if ((m = _labeledRule.firstMatch(line)) != null) {
        children.add(_labeledDivider(m!.group(1)!));
      } else if ((m = _bullet.firstMatch(line)) != null) {
        children.add(_listItem(m!.group(1)!, '•', m.group(2)!));
      } else if ((m = _numbered.firstMatch(line)) != null) {
        children.add(_listItem(m!.group(1)!, '${m.group(2)}.', m.group(3)!));
      } else if ((m = _quote.firstMatch(line)) != null) {
        children.add(_quoteWidget(m!.group(1)!));
      } else {
        children.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 2 * s),
          child: Text.rich(TextSpan(children: _spans(line, _base))),
        ));
      }
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  // ------------------------------------------------------------- bloklar
  Widget _headingWidget(int level, String text) {
    const sizes = [1.7, 1.45, 1.25, 1.12, 1.05, 1.0];
    final style = _base.copyWith(
      fontSize: 15 * s * sizes[level - 1],
      fontWeight: FontWeight.w800,
      color: level <= 2 ? Colors.white : AppColors.text,
      height: 1.3,
    );
    return Padding(
      padding: EdgeInsets.only(top: 10 * s, bottom: 4 * s),
      child: Text.rich(TextSpan(children: _spans(text, style))),
    );
  }

  Widget _taskWidget(List<String> lines, int idx, Match m) {
    final indent = m.group(1)!.replaceAll('\t', '  ').length ~/ 2;
    final done = m.group(2)!.toLowerCase() == 'x';
    final text = m.group(3)!;
    final style = done
        ? _base.copyWith(
            color: AppColors.muted,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.muted,
          )
        : _base;

    void toggle() {
      final updated = List<String>.of(lines);
      final line = updated[idx];
      final pos = line.indexOf('[');
      updated[idx] = line.replaceRange(pos, pos + 3, done ? '[ ]' : '[x]');
      widget.onChanged?.call(updated.join('\n'));
    }

    final box = Container(
      width: 20 * s,
      height: 20 * s,
      margin: EdgeInsets.only(top: 2 * s),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.done : Colors.transparent,
        border: Border.all(
          color: done ? AppColors.done : AppColors.muted,
          width: 1.6 * s,
        ),
      ),
      child: done ? Icon(Icons.check, size: 14 * s, color: AppColors.bg) : null,
    );

    return Padding(
      padding: EdgeInsets.only(left: indent * 22.0 * s, top: 4 * s, bottom: 4 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.interactive && widget.onChanged != null
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  child: Padding(padding: EdgeInsets.all(2 * s), child: box),
                )
              : Padding(padding: EdgeInsets.all(2 * s), child: box),
          SizedBox(width: 10 * s),
          Expanded(child: Text.rich(TextSpan(children: _spans(text, style)))),
        ],
      ),
    );
  }

  Widget _listItem(String indentStr, String marker, String text) {
    final indent = indentStr.replaceAll('\t', '  ').length ~/ 2;
    return Padding(
      padding: EdgeInsets.only(left: 6 * s + indent * 22.0 * s, top: 2 * s, bottom: 2 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20 * s,
            child: Text(marker, style: _base.copyWith(color: AppColors.accentSoft)),
          ),
          Expanded(child: Text.rich(TextSpan(children: _spans(text, _base)))),
        ],
      ),
    );
  }

  Widget _quoteWidget(String text) => Container(
        margin: EdgeInsets.symmetric(vertical: 4 * s),
        padding: EdgeInsets.fromLTRB(12 * s, 6 * s, 8 * s, 6 * s),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          border: Border(left: BorderSide(color: AppColors.accent, width: 3 * s)),
        ),
        child: Text.rich(TextSpan(
          children: _spans(text, _base.copyWith(fontStyle: FontStyle.italic)),
        )),
      );

  Widget _embedPlaceholder(String target) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 8 * s),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8 * s),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.draw_rounded, size: 16 * s, color: AppColors.accentSoft),
            SizedBox(width: 6 * s),
            Expanded(
              child: Text(target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _base.copyWith(color: AppColors.accentSoft)),
            ),
          ],
        ),
      );

  Widget _codeBlock(String code) => Container(
        margin: EdgeInsets.symmetric(vertical: 6 * s),
        padding: EdgeInsets.all(12 * s),
        decoration: BoxDecoration(
          color: AppColors.code,
          borderRadius: BorderRadius.circular(8 * s),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.5 * s,
              color: AppColors.codeText,
              height: 1.4,
            ),
          ),
        ),
      );

  Widget _divider() => Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        child: CustomPaint(
          size: Size(double.infinity, 2 * s),
          painter: _DashPainter(AppColors.separator, 1.4 * s),
        ),
      );

  Widget _labeledDivider(String label) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * s),
        child: Row(
          children: [
            Text.rich(TextSpan(
              children: _spans(
                label,
                _base.copyWith(color: AppColors.separator, fontWeight: FontWeight.w600),
              ),
            )),
            SizedBox(width: 8 * s),
            Expanded(
              child: CustomPaint(
                size: Size(double.infinity, 2 * s),
                painter: _DashPainter(AppColors.separator, 1.4 * s),
              ),
            ),
          ],
        ),
      );

  // ------------------------------------------------------------- satır içi
  List<InlineSpan> _spans(String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      if (m.group(1) != null) {
        spans.addAll(_spans(m.group(2)!, style.copyWith(fontWeight: FontWeight.w700)));
      } else if (m.group(3) != null) {
        spans.addAll(_spans(
          m.group(4)!,
          style.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (m.group(5) != null) {
        spans.addAll(_spans(
          m.group(6)!,
          style.copyWith(
            backgroundColor: AppColors.highlight,
            color: AppColors.highlightText,
          ),
        ));
      } else if (m.group(7) != null) {
        spans.add(TextSpan(
          text: ' ${m.group(8)} ',
          style: style.copyWith(
            fontFamily: 'monospace',
            fontSize: (style.fontSize ?? 15) * 0.9,
            backgroundColor: AppColors.code,
            color: AppColors.codeText,
          ),
        ));
      } else if (m.group(9) != null) {
        final inner = m.group(10)!;
        final parts = inner.split('|');
        final target = parts.first.split('#').first.trim();
        final label = parts.length > 1 ? parts.sublist(1).join('|') : parts.first;
        final exists = widget.linkExists?.call(target) ?? true;
        spans.add(TextSpan(
          text: label,
          style: style.copyWith(
            color: exists ? AppColors.accentSoft : AppColors.missingLink,
            decoration: TextDecoration.underline,
            decorationColor:
                (exists ? AppColors.accentSoft : AppColors.missingLink).withValues(alpha: 0.5),
          ),
          recognizer: _tap(() => widget.onLinkTap?.call(target)),
        ));
      } else if (m.group(11) != null) {
        spans.addAll(_spans(m.group(12)!, style.copyWith(fontStyle: FontStyle.italic)));
      } else if (m.group(13) != null) {
        final tag = m.group(13)!;
        spans.add(TextSpan(
          text: tag,
          style: style.copyWith(
            color: AppColors.tag,
            backgroundColor: AppColors.tag.withValues(alpha: 0.12),
          ),
          recognizer: _tap(() => widget.onTagTap?.call(tag.substring(1).toLowerCase())),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return spans;
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.thickness);
  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    final y = size.height / 2;
    const dash = 6.0, gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width).toDouble(), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.thickness != thickness;
}
