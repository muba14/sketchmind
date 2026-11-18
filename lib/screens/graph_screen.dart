import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../theme.dart';

const double _world = 2400;

enum _NodeKind { text, sketch, missing, tag }

class _Node {
  _Node(this.key, this.label, this.kind, this.pos);
  final String key; // not id, "missing:başlık" ya da "tag:etiket"
  final String label;
  final _NodeKind kind;
  Offset pos;
  Offset vel = Offset.zero;
  int degree = 0;

  double get radius => 7 + sqrt(degree.toDouble()) * 4;
}

/// Obsidian'daki gibi, notların bağlantılarını gösteren kuvvet yönelimli grafik.
class GraphPage extends StatefulWidget {
  const GraphPage({super.key});

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> with SingleTickerProviderStateMixin {
  final Map<String, _Node> _nodes = {};
  final List<(String, String)> _edges = [];
  final _tick = ValueNotifier<int>(0);
  final _tc = TransformationController();
  late final Ticker _ticker;
  String _signature = '';
  int _steps = 0;
  bool _showTags = false;
  bool _showOrphans = true;
  String? _selected;
  bool _centered = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _step());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tick.dispose();
    _tc.dispose();
    super.dispose();
  }

  /// Notlardan düğüm ve kenarları kurar; mevcut düğümlerin konumunu korur.
  void _rebuild(NoteStore store) {
    final sig = StringBuffer('$_showTags|$_showOrphans|');
    for (final n in store.notes) {
      sig.write('${n.id}:${n.title}:${n.links.join(',')}:${_showTags ? n.tags.join(',') : ''};');
    }
    final s = sig.toString();
    if (s == _signature) return;
    _signature = s;

    final old = Map.of(_nodes);
    _nodes.clear();
    _edges.clear();
    final rand = Random(42);
    const c = Offset(_world / 2, _world / 2);

    _Node make(String key, String label, _NodeKind kind) {
      final prev = old[key];
      if (prev != null) {
        final n = _Node(key, label, kind, prev.pos);
        _nodes[key] = n;
        return n;
      }
      final a = rand.nextDouble() * pi * 2;
      final r = 80 + rand.nextDouble() * 260;
      final n = _Node(key, label, kind, c + Offset(cos(a) * r, sin(a) * r));
      _nodes[key] = n;
      return n;
    }

    final titleToId = <String, String>{};
    for (final n in store.notes) {
      make(n.id, n.displayTitle, n.type == NoteType.sketch ? _NodeKind.sketch : _NodeKind.text);
      if (!n.isUntitled) titleToId[n.title.trim().toLowerCase()] = n.id;
    }
    for (final n in store.notes) {
      for (final l in n.links) {
        final target = titleToId[l.toLowerCase()];
        final key = target ?? 'missing:${l.toLowerCase()}';
        if (target == null) make(key, l, _NodeKind.missing);
        if (key != n.id) _edges.add((n.id, key));
      }
      if (_showTags) {
        for (final t in n.tags) {
          final key = 'tag:$t';
          make(key, '#$t', _NodeKind.tag);
          _edges.add((n.id, key));
        }
      }
    }
    for (final e in _edges) {
      _nodes[e.$1]!.degree++;
      _nodes[e.$2]!.degree++;
    }
    if (!_showOrphans) {
      _nodes.removeWhere((_, n) => n.degree == 0);
    }
    if (_selected != null && !_nodes.containsKey(_selected)) _selected = null;
    _steps = 0;
    if (!_ticker.isActive) _ticker.start();
  }

  void _step() {
    final nodes = _nodes.values.toList();
    const center = Offset(_world / 2, _world / 2);
    // İtme
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i], b = nodes[j];
        var d = a.pos - b.pos;
        var dist2 = d.distanceSquared;
        if (dist2 < 0.01) {
          d = Offset(Random().nextDouble() - 0.5, Random().nextDouble() - 0.5);
          dist2 = 0.5;
        }
        final f = 9000 / dist2;
        final dist = sqrt(dist2);
        final push = d / dist * min(f, 40);
        a.vel += push;
        b.vel -= push;
      }
    }
    // Yaylar
    for (final e in _edges) {
      final a = _nodes[e.$1], b = _nodes[e.$2];
      if (a == null || b == null) continue;
      final d = b.pos - a.pos;
      final dist = max(d.distance, 0.01);
      final f = (dist - 130) * 0.02;
      final pull = d / dist * f;
      a.vel += pull;
      b.vel -= pull;
    }
    var energy = 0.0;
    for (final n in nodes) {
      n.vel += (center - n.pos) * 0.004;
      n.vel *= 0.82;
      n.pos += n.vel;
      energy += n.vel.distanceSquared;
    }
    _steps++;
    _tick.value++;
    if (_steps > 900 || (_steps > 60 && energy < 0.02 * max(nodes.length, 1))) {
      _ticker.stop();
    }
  }

  void _onTap(Offset p) {
    String? hit;
    var best = double.infinity;
    for (final n in _nodes.values) {
      final d = (n.pos - p).distance;
      if (d < n.radius + 18 && d < best) {
        best = d;
        hit = n.key;
      }
    }
    setState(() => _selected = hit);
    _tick.value++;
  }

  Future<void> _openSelected(NoteStore store) async {
    final key = _selected;
    if (key == null) return;
    final node = _nodes[key];
    if (node == null) return;
    switch (node.kind) {
      case _NodeKind.missing:
        await openOrCreateByTitle(context, node.label);
      case _NodeKind.tag:
        break;
      case _NodeKind.text:
      case _NodeKind.sketch:
        final n = store.byId(key);
        if (n != null) await openNote(context, n);
    }
  }

  void _center(Size viewport) {
    final s = viewport.width < 500 ? 0.8 : 1.0;
    _tc.value = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, viewport.width / 2 - _world / 2 * s)
      ..setEntry(1, 3, viewport.height / 2 - _world / 2 * s);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NoteStore>();
    _rebuild(store);
    final sel = _selected == null ? null : _nodes[_selected];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grafik'),
        actions: [
          IconButton(
            tooltip: 'Yeniden düzenle',
            onPressed: () {
              _signature = '';
              for (final n in _nodes.values) {
                n.vel = Offset.zero;
              }
              final rand = Random();
              for (final n in _nodes.values) {
                n.pos += Offset(rand.nextDouble() * 60 - 30, rand.nextDouble() * 60 - 30);
              }
              _steps = 0;
              if (!_ticker.isActive) _ticker.start();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          LayoutBuilder(builder: (context, c) {
            if (!_centered) {
              _centered = true;
              _center(c.biggest);
            }
            return InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              minScale: 0.15,
              maxScale: 4,
              boundaryMargin: const EdgeInsets.all(800),
              child: GestureDetector(
                onTapUp: (d) => _onTap(d.localPosition),
                child: CustomPaint(
                  size: const Size(_world, _world),
                  painter: _GraphPainter(
                    nodes: _nodes,
                    edges: _edges,
                    selected: _selected,
                    repaint: _tick,
                  ),
                ),
              ),
            );
          }),
          Positioned(
            left: 12,
            top: 8,
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Etiketler'),
                  selected: _showTags,
                  onSelected: (v) => setState(() => _showTags = v),
                  backgroundColor: AppColors.card,
                  selectedColor: AppColors.accent.withValues(alpha: 0.4),
                  side: BorderSide.none,
                ),
                FilterChip(
                  label: const Text('Bağlantısızlar'),
                  selected: _showOrphans,
                  onSelected: (v) => setState(() => _showOrphans = v),
                  backgroundColor: AppColors.card,
                  selectedColor: AppColors.accent.withValues(alpha: 0.4),
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          if (sel != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                elevation: 6,
                child: ListTile(
                  leading: Icon(
                    switch (sel.kind) {
                      _NodeKind.text => Icons.description_outlined,
                      _NodeKind.sketch => Icons.draw_rounded,
                      _NodeKind.missing => Icons.add_circle_outline,
                      _NodeKind.tag => Icons.tag_rounded,
                    },
                    color: AppColors.accentSoft,
                  ),
                  title: Text(sel.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    sel.kind == _NodeKind.missing
                        ? 'Henüz oluşturulmamış not'
                        : '${sel.degree} bağlantı',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  trailing: sel.kind == _NodeKind.tag
                      ? null
                      : FilledButton(
                          onPressed: () => _openSelected(store),
                          child: Text(sel.kind == _NodeKind.missing ? 'Oluştur' : 'Aç'),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.selected,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Map<String, _Node> nodes;
  final List<(String, String)> edges;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final neighbors = <String>{};
    if (selected != null) {
      neighbors.add(selected!);
      for (final e in edges) {
        if (e.$1 == selected) neighbors.add(e.$2);
        if (e.$2 == selected) neighbors.add(e.$1);
      }
    }
    final dim = selected != null;

    final edgePaint = Paint()..strokeWidth = 1.4;
    for (final e in edges) {
      final a = nodes[e.$1], b = nodes[e.$2];
      if (a == null || b == null) continue;
      final hot = dim && (e.$1 == selected || e.$2 == selected);
      edgePaint.color = hot
          ? AppColors.accent
          : AppColors.muted.withValues(alpha: dim ? 0.12 : 0.35);
      edgePaint.strokeWidth = hot ? 2.4 : 1.4;
      canvas.drawLine(a.pos, b.pos, edgePaint);
    }

    for (final n in nodes.values) {
      final faded = dim && !neighbors.contains(n.key);
      final base = switch (n.kind) {
        _NodeKind.text => const Color(0xFFC9C9D6),
        _NodeKind.sketch => const Color(0xFFFF8A5B),
        _NodeKind.missing => const Color(0xFF6A6A7A),
        _NodeKind.tag => AppColors.tag,
      };
      final color = n.key == selected ? AppColors.accent : base;
      canvas.drawCircle(
        n.pos,
        n.radius,
        Paint()..color = color.withValues(alpha: faded ? 0.25 : 1),
      );
      if (n.key == selected) {
        canvas.drawCircle(
          n.pos,
          n.radius + 5,
          Paint()
            ..color = AppColors.accent.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: n.label.length > 28 ? '${n.label.substring(0, 27)}…' : n.label,
          style: TextStyle(
            color: AppColors.text.withValues(alpha: faded ? 0.25 : 0.9),
            fontSize: 13,
            fontStyle: n.kind == _NodeKind.missing ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, n.pos + Offset(-tp.width / 2, n.radius + 4));
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
