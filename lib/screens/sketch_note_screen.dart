import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../data/media_cache.dart';
import '../data/note_store.dart';
import '../models/note.dart';
import '../navigation.dart';
import '../security/lock.dart';
import '../sketch/shape_recognizer.dart';
import '../theme.dart';
import '../widgets/sketch_painter.dart';

enum SketchTool { pen, highlighter, eraser, lasso, hand }

enum _DragMode { move, scale }

const _palette = <int>[
  0xFFFF6B35, // turuncu
  0xFFE5484D, // kırmızı
  0xFFF5C542, // sarı
  0xFF4CC38A, // yeşil
  0xFF3E8BFF, // mavi
  0xFF8B6CF6, // mor
  0xFFFFFFFF, // beyaz
  0xFF111111, // siyah
];

const _paperColors = <int>[
  0xFFFFFFFF, // beyaz
  0xFFFFF8E7, // krem
  0xFF1F1F27, // koyu mor-gri
  0xFF000000, // siyah
  0xFF1E2A24, // koyu yeşil (yazı tahtası)
];

/// Sayfa padding'i (InteractiveViewer içindeki boşluk).
const double _pad = 12;

class _Snapshot {
  const _Snapshot(this.strokes, this.images, this.pages);
  final List<Stroke> strokes;
  final List<SketchImage> images;
  final int pages;
}

/// Squid tarzı el yazısı/çizim sayfası.
class SketchNoteScreen extends StatefulWidget {
  const SketchNoteScreen({super.key, required this.noteId});
  final String noteId;

  @override
  State<SketchNoteScreen> createState() => _SketchNoteScreenState();
}

class _SketchNoteScreenState extends State<SketchNoteScreen> {
  late final NoteStore _store;
  Note? _note;

  SketchTool _tool = SketchTool.pen;
  int _color = _palette.first;
  double _penWidth = 6;
  double _highlighterWidth = 28;
  double _eraserSize = 24;
  bool _stylusOnly = false;
  bool _shapeAssist = true;

  final _active = ValueNotifier<Stroke?>(null);
  final _lasso = ValueNotifier<List<Offset>>(const []);
  final _undo = <_Snapshot>[];
  final _redo = <_Snapshot>[];
  final _tc = TransformationController();
  final _pointers = <int>{};
  int? _drawingPointer;
  bool _erasedThisGesture = false;
  int _version = 0;

  // Şekil düzeltme (kalemi sabit tutunca)
  Timer? _holdTimer;
  Offset _holdAnchor = Offset.zero;
  bool _snapped = false;

  // Kement seçimi
  List<int> _selStrokes = const [];
  List<String> _selImages = const [];
  Rect? _selRect;
  _DragMode? _drag;
  Offset _dragStart = Offset.zero;
  Rect _origRect = Rect.zero;
  List<Stroke> _origStrokes = const [];
  List<SketchImage> _origImages = const [];

  // Yerleşim
  double _scale = 1;
  Size _viewport = Size.zero;
  double? _progress; // PDF içe aktarma ilerlemesi

  @override
  void initState() {
    super.initState();
    _store = context.read<NoteStore>();
    _note = _store.byId(widget.noteId);
    final n = _note;
    if (n != null && n.strokes.isEmpty) {
      _color = isDarkPaper(Color(n.paperColor)) ? _palette.first : 0xFF111111;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _active.dispose();
    _lasso.dispose();
    _tc.dispose();
    super.dispose();
  }

  double get _zoom => _tc.value.getMaxScaleOnAxis();
  bool get _hasSelection => _selRect != null;

  // ------------------------------------------------------------ işaretçi olayları
  bool _accepts(PointerEvent e) {
    if (_tool == SketchTool.hand) return false;
    if (_stylusOnly &&
        e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus &&
        e.kind != PointerDeviceKind.mouse) {
      return false;
    }
    return true;
  }

  void _down(PointerDownEvent e) {
    if (!_accepts(e)) return;
    _pointers.add(e.pointer);
    if (_pointers.length > 1) {
      // İki parmak = yakınlaştırma; yarım işlemi iptal et.
      _holdTimer?.cancel();
      _active.value = null;
      _lasso.value = const [];
      _drawingPointer = null;
      if (_drag != null) _cancelDrag();
      return;
    }
    _drawingPointer = e.pointer;
    final p = e.localPosition / _scale;

    if (_tool == SketchTool.lasso) {
      _lassoDown(p);
      return;
    }
    final eraser = _tool == SketchTool.eraser || e.kind == PointerDeviceKind.invertedStylus;
    if (eraser) {
      _erasedThisGesture = false;
      _eraseAt(p);
      return;
    }
    final hl = _tool == SketchTool.highlighter;
    _snapped = false;
    _active.value = Stroke(
      points: [p],
      color: _color,
      width: hl ? _highlighterWidth : _penWidth,
      highlighter: hl,
    );
    _armHold(p);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _drawingPointer) return;
    final p = e.localPosition / _scale;
    if (_tool == SketchTool.lasso) {
      _lassoMove(p);
      return;
    }
    final cur = _active.value;
    if (cur == null) {
      _eraseAt(p);
      return;
    }
    if (_snapped) return; // şekil oluştu; kaldırınca kaydedilecek
    if ((cur.points.last - p).distance < 1.2) return;
    _active.value = cur.copyWith(points: [...cur.points, p]);
    if ((p - _holdAnchor).distance > 6 / _zoom) _armHold(p);
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer != _drawingPointer) return;
    _drawingPointer = null;
    _holdTimer?.cancel();
    if (_tool == SketchTool.lasso) {
      _lassoUp();
      return;
    }
    final st = _active.value;
    _active.value = null;
    final n = _note;
    if (st == null || n == null) return;
    _pushUndo(n);
    n.strokes = [...n.strokes, st];
    _save(n);
  }

  void _cancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _drawingPointer) {
      _drawingPointer = null;
      _holdTimer?.cancel();
      _active.value = null;
      _lasso.value = const [];
      if (_drag != null) _cancelDrag();
    }
  }

  // ------------------------------------------------------------ şekil düzeltme
  void _armHold(Offset p) {
    if (!_shapeAssist) return;
    _holdAnchor = p;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 550), _trySnap);
  }

  void _trySnap() {
    final cur = _active.value;
    if (cur == null || _snapped || _drawingPointer == null) return;
    final shape = recognizeShape(cur);
    if (shape == null) return;
    _snapped = true;
    _active.value = shape;
    HapticFeedback.selectionClick();
  }

  // ------------------------------------------------------------ silgi
  void _eraseAt(Offset p) {
    final n = _note;
    if (n == null) return;
    final remaining = n.strokes.where((s) => !s.hits(p, _eraserSize)).toList();
    if (remaining.length == n.strokes.length) return;
    if (!_erasedThisGesture) {
      _pushUndo(n);
      _erasedThisGesture = true;
    }
    n.strokes = remaining;
    _save(n);
  }

  // ------------------------------------------------------------ kement
  void _lassoDown(Offset p) {
    final r = _selRect;
    if (r != null) {
      final handle = 34 / (_scale * _zoom);
      if ((p - r.bottomRight).distance <= handle) {
        _beginDrag(_DragMode.scale, p);
        return;
      }
      if (r.inflate(6 / (_scale * _zoom)).contains(p)) {
        _beginDrag(_DragMode.move, p);
        return;
      }
    }
    setState(_clearSelection);
    _lasso.value = [p];
  }

  void _lassoMove(Offset p) {
    if (_drag != null) {
      _applyDrag(p);
      return;
    }
    if (_lasso.value.isEmpty) return;
    _lasso.value = [..._lasso.value, p];
  }

  void _lassoUp() {
    final n = _note;
    if (n == null) return;
    if (_drag != null) {
      _drag = null;
      _save(n);
      return;
    }
    final poly = _lasso.value;
    _lasso.value = const [];
    if (poly.length < 3) return;

    final strokes = <int>[];
    Rect? bounds;
    for (var i = 0; i < n.strokes.length; i++) {
      final s = n.strokes[i];
      var inside = 0;
      for (final pt in s.points) {
        if (pointInPolygon(pt, poly)) inside++;
      }
      if (inside > 0 && inside * 2 >= s.points.length) {
        strokes.add(i);
        bounds = bounds == null ? s.bounds : bounds.expandToInclude(s.bounds);
      }
    }
    final images = <String>[];
    for (final im in n.images) {
      if (!im.background && pointInPolygon(im.rect.center, poly)) {
        images.add(im.id);
        bounds = bounds == null ? im.rect : bounds.expandToInclude(im.rect);
      }
    }
    setState(() {
      _selStrokes = strokes;
      _selImages = images;
      _selRect = bounds;
    });
  }

  void _clearSelection() {
    _selStrokes = const [];
    _selImages = const [];
    _selRect = null;
    _drag = null;
  }

  void _beginDrag(_DragMode mode, Offset p) {
    final n = _note!;
    _pushUndo(n);
    _drag = mode;
    _dragStart = p;
    _origRect = _selRect!;
    _origStrokes = n.strokes;
    _origImages = n.images;
  }

  void _cancelDrag() {
    final n = _note!;
    n.strokes = _origStrokes;
    n.images = _origImages;
    _undo.removeLast();
    setState(() {
      _selRect = _origRect;
      _drag = null;
      _version++;
    });
  }

  void _applyDrag(Offset p) {
    final n = _note!;
    late final Offset Function(Offset) f;
    var k = 1.0;
    if (_drag == _DragMode.move) {
      final d = p - _dragStart;
      f = (q) => q + d;
    } else {
      final anchor = _origRect.topLeft;
      final kx = (p.dx - anchor.dx) / max(_origRect.width, 1);
      final ky = (p.dy - anchor.dy) / max(_origRect.height, 1);
      k = ((kx + ky) / 2).clamp(0.15, 8.0).toDouble();
      f = (q) => anchor + (q - anchor) * k;
    }
    final sel = _selStrokes.toSet();
    final selImg = _selImages.toSet();
    n.strokes = [
      for (var i = 0; i < _origStrokes.length; i++)
        sel.contains(i) ? _origStrokes[i].transformed(f, widthScale: k) : _origStrokes[i],
    ];
    n.images = [
      for (final im in _origImages)
        selImg.contains(im.id)
            ? im.withRect(Rect.fromPoints(f(im.rect.topLeft), f(im.rect.bottomRight)))
            : im,
    ];
    setState(() {
      _selRect = Rect.fromPoints(f(_origRect.topLeft), f(_origRect.bottomRight));
      _version++;
    });
  }

  void _deleteSelection() {
    final n = _note!;
    _pushUndo(n);
    final sel = _selStrokes.toSet();
    final selImg = _selImages.toSet();
    n.strokes = [
      for (var i = 0; i < n.strokes.length; i++)
        if (!sel.contains(i)) n.strokes[i],
    ];
    n.images = [for (final im in n.images) if (!selImg.contains(im.id)) im];
    setState(_clearSelection);
    _save(n);
  }

  void _duplicateSelection() {
    final n = _note!;
    _pushUndo(n);
    const d = Offset(40, 40);
    final copies = [for (final i in _selStrokes) n.strokes[i].transformed((q) => q + d)];
    final imgCopies = [
      for (final im in n.images)
        if (_selImages.contains(im.id))
          SketchImage(id: Note.newId(), media: im.media, rect: im.rect.shift(d)),
    ];
    final start = n.strokes.length;
    n.strokes = [...n.strokes, ...copies];
    n.images = [...n.images, ...imgCopies];
    setState(() {
      _selStrokes = [for (var i = 0; i < copies.length; i++) start + i];
      _selImages = [for (final im in imgCopies) im.id];
      _selRect = _selRect!.shift(d);
    });
    _save(n);
  }

  // ------------------------------------------------------------ geri al / kaydet
  void _pushUndo(Note n) {
    _undo.add(_Snapshot(n.strokes, n.images, n.pages));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void _save(Note n) {
    _version++;
    _store.update(n);
  }

  void _restore(Note n, _Snapshot s) {
    n.strokes = s.strokes;
    n.images = s.images;
    n.pages = s.pages;
    setState(_clearSelection);
    _save(n);
  }

  void _doUndo() {
    final n = _note;
    if (n == null || _undo.isEmpty) return;
    _redo.add(_Snapshot(n.strokes, n.images, n.pages));
    _restore(n, _undo.removeLast());
  }

  void _doRedo() {
    final n = _note;
    if (n == null || _redo.isEmpty) return;
    _undo.add(_Snapshot(n.strokes, n.images, n.pages));
    _restore(n, _redo.removeLast());
  }

  // ------------------------------------------------------------ fotoğraf / PDF
  Offset _visibleCenter() {
    final scene = _tc.toScene(Offset(_viewport.width / 2, _viewport.height / 2));
    final p = (scene - const Offset(_pad, _pad)) / _scale;
    final maxY = kPageHeight * (_note?.pages ?? 1);
    return Offset(
      p.dx.clamp(200.0, kPageWidth - 200).toDouble(),
      p.dy.clamp(200.0, max(200.0, maxY - 200)).toDouble(),
    );
  }

  void _attachSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden fotoğraf'),
              onTap: () {
                Navigator.pop(ctx);
                _insertPhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamerayla çek'),
              onTap: () {
                Navigator.pop(ctx);
                _insertPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF içe aktar'),
              subtitle: const Text('Her PDF sayfası ayrı bir not sayfası olur',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _importPdf();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _insertPhoto(ImageSource source) async {
    final n = _note;
    if (n == null) return;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      final aspect = decoded.height / decoded.width;
      decoded.dispose();
      final dot = x.name.lastIndexOf('.');
      final ext = dot > 0 ? x.name.substring(dot + 1).toLowerCase() : 'jpg';
      final name = await _store.saveMedia(bytes, ext);
      var w = 600.0, h = w * aspect;
      if (h > 800) {
        h = 800;
        w = h / aspect;
      }
      final img = SketchImage(
        id: Note.newId(),
        media: name,
        rect: Rect.fromCenter(center: _visibleCenter(), width: w, height: h),
      );
      _pushUndo(n);
      n.images = [...n.images, img];
      // Hemen taşınabilsin diye seçili gelsin.
      setState(() {
        _tool = SketchTool.lasso;
        _selStrokes = const [];
        _selImages = [img.id];
        _selRect = img.rect;
      });
      _save(n);
    } catch (e) {
      _snack('Fotoğraf eklenemedi: $e');
    }
  }

  Future<void> _importPdf() async {
    final n = _note;
    if (n == null) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.single;
    setState(() => _progress = 0);
    try {
      final Uint8List bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
      final fresh = n.strokes.isEmpty && n.images.isEmpty;
      final start = fresh ? 0 : n.pages;
      final added = <SketchImage>[];
      var index = 0;
      // Her PDF sayfası bir görsele çevrilir (Android'de PdfRenderer, iOS'ta PDFKit).
      await for (final page in Printing.raster(bytes, dpi: 120)) {
        final png = await page.toPng();
        final rw = page.width.toDouble();
        final rh = page.height.toDouble();
        final name = await _store.saveMedia(png, 'png');
        var w = kPageWidth, h = kPageWidth * rh / rw;
        if (h > kPageHeight) {
          h = kPageHeight;
          w = h * rw / rh;
        }
        added.add(SketchImage(
          id: Note.newId(),
          media: name,
          rect: Rect.fromLTWH((kPageWidth - w) / 2, (start + index) * kPageHeight, w, h),
          background: true,
        ));
        index++;
      }
      if (added.isEmpty) throw StateError('PDF boş');
      _pushUndo(n);
      n.images = [...n.images, ...added];
      n.pages = max(n.pages, start + added.length);
      if (fresh) {
        // Slaytların altına yazmak için açık renkli çizgili kağıt.
        n.paper = PaperType.lined;
        n.paperColor = 0xFFFFFFFF;
        _color = 0xFF3E8BFF;
        if (n.isUntitled) {
          n.title = picked.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        }
      }
      _save(n);
      _snack('${added.length} sayfa eklendi');
    } catch (e) {
      _snack('PDF açılamadı: $e');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ arayüz
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
        title: GestureDetector(
          onTap: () => _rename(note),
          child: Text(
            note.displayTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontStyle: note.isUntitled ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Geri al',
            onPressed: _undo.isEmpty ? null : _doUndo,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Yinele',
            onPressed: _redo.isEmpty ? null : _doRedo,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: 'Fotoğraf / PDF ekle',
            onPressed: _attachSheet,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          PopupMenuButton<String>(
            color: AppColors.surface,
            onSelected: (v) async {
              switch (v) {
                case 'paper':
                  _paperSheet(note);
                case 'page':
                  _pushUndo(note);
                  note.pages += 1;
                  _save(note);
                case 'shape':
                  setState(() => _shapeAssist = !_shapeAssist);
                case 'stylus':
                  setState(() => _stylusOnly = !_stylusOnly);
                case 'clear':
                  if (note.strokes.isEmpty) return;
                  _pushUndo(note);
                  note.strokes = [];
                  setState(_clearSelection);
                  _save(note);
                case 'more':
                  final deleted = await showNoteActions(context, note);
                  if (deleted && context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'paper', child: Text('Kağıt tipi ve rengi')),
              const PopupMenuItem(value: 'page', child: Text('Sayfa ekle')),
              CheckedPopupMenuItem(
                value: 'shape',
                checked: _shapeAssist,
                child: const Text('Şekil düzeltme'),
              ),
              CheckedPopupMenuItem(
                value: 'stylus',
                checked: _stylusOnly,
                child: const Text('Sadece kalemle çiz'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Çizimleri temizle')),
              const PopupMenuItem(value: 'more', child: Text('Not seçenekleri…')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _toolbar(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _canvas(note)),
                if (_hasSelection) _selectionBar(),
                if (_progress != null) _progressOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvas(Note note) {
    final media = context.read<MediaCache>();
    return LayoutBuilder(builder: (context, c) {
      _viewport = c.biggest;
      final w = c.maxWidth - _pad * 2;
      _scale = w / kPageWidth;
      final h = kPageHeight * _scale * note.pages;
      final canMove = _tool == SketchTool.hand || _stylusOnly;
      return Container(
        color: const Color(0xFF141419),
        child: InteractiveViewer(
          transformationController: _tc,
          constrained: false,
          minScale: 0.5,
          maxScale: 6,
          panEnabled: canMove,
          boundaryMargin: const EdgeInsets.all(120),
          child: Padding(
            padding: const EdgeInsets.all(_pad),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _cancel,
              child: _stylusClaim(Container(
                decoration: const BoxDecoration(
                  boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12)],
                ),
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: Size(w, h),
                          painter: SketchPainter(
                            strokes: note.strokes,
                            images: note.images,
                            media: media,
                            paper: note.paper,
                            paperColor: Color(note.paperColor),
                            pages: note.pages,
                            version: _version,
                          ),
                        ),
                      ),
                      CustomPaint(
                        size: Size(w, h),
                        painter: ActiveStrokePainter(_active),
                      ),
                      CustomPaint(
                        size: Size(w, h),
                        painter: _SelectionPainter(
                          lasso: _lasso,
                          selection: _selRect,
                          zoom: _zoom,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
            ),
          ),
        ),
      );
    });
  }

  Widget _selectionBar() {
    final count = _selStrokes.length + _selImages.length;
    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: AppColors.surface,
          elevation: 6,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$count öğe',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
                IconButton(
                  tooltip: 'Çoğalt',
                  onPressed: _duplicateSelection,
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: _deleteSelection,
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.separator),
                ),
                IconButton(
                  tooltip: 'Seçimi kaldır',
                  onPressed: () => setState(_clearSelection),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressOverlay() => Positioned.fill(
        child: Container(
          color: const Color(0x99000000),
          alignment: Alignment.center,
          child: Container(
            width: 240,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('PDF içe aktarılıyor…',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              ],
            ),
          ),
        ),
      );

  /// "Sadece kalem" modunda parmak kaydırır; kalem hareketini kaydırmaya
  /// kaptırmamak için kalem dokunuşlarını burada sahipleniyoruz.
  Widget _stylusClaim(Widget child) {
    if (!_stylusOnly || _tool == SketchTool.hand) return child;
    return GestureDetector(
      supportedDevices: const {PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
      onPanStart: (_) {},
      onPanUpdate: (_) {},
      child: child,
    );
  }

  Widget _toolbar() {
    Widget tool(SketchTool t, IconData icon, String tip) {
      final sel = _tool == t;
      return IconButton(
        tooltip: tip,
        onPressed: () {
          final sized = t == SketchTool.pen ||
              t == SketchTool.highlighter ||
              t == SketchTool.eraser;
          if (sel && sized) {
            _widthSheet();
          } else {
            setState(() {
              _tool = t;
              if (t != SketchTool.lasso) _clearSelection();
            });
          }
        },
        style: IconButton.styleFrom(
          backgroundColor: sel ? AppColors.accent.withValues(alpha: 0.25) : null,
        ),
        icon: Icon(icon, color: sel ? AppColors.accentSoft : AppColors.text),
      );
    }

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tool(SketchTool.pen, Icons.edit_rounded,
                'Kalem (tekrar dokun: kalınlık, sonda basılı tut: şekil)'),
            tool(SketchTool.highlighter, Icons.border_color_rounded, 'Fosforlu kalem'),
            tool(SketchTool.eraser, Icons.auto_fix_normal_rounded, 'Silgi'),
            tool(SketchTool.lasso, Icons.gesture_rounded, 'Kement: seç, taşı, büyüt'),
            tool(SketchTool.hand, Icons.pan_tool_alt_rounded, 'Kaydır / yakınlaştır'),
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.border,
            ),
            for (final c in _palette)
              GestureDetector(
                onTap: () => setState(() {
                  _color = c;
                  if (_tool == SketchTool.eraser ||
                      _tool == SketchTool.hand ||
                      _tool == SketchTool.lasso) {
                    _tool = SketchTool.pen;
                    _clearSelection();
                  }
                }),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _color == c ? AppColors.accentSoft : AppColors.border,
                      width: _color == c ? 3 : 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _widthSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isEraser = _tool == SketchTool.eraser;
          final isHl = _tool == SketchTool.highlighter;
          final value = isEraser ? _eraserSize : (isHl ? _highlighterWidth : _penWidth);
          final min = isEraser ? 8.0 : (isHl ? 12.0 : 2.0);
          final max = isEraser ? 80.0 : (isHl ? 60.0 : 30.0);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEraser ? 'Silgi boyutu' : (isHl ? 'Fosforlu kalınlığı' : 'Kalem kalınlığı'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Slider(
                    value: value.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    onChanged: (v) {
                      setState(() {
                        if (isEraser) {
                          _eraserSize = v;
                        } else if (isHl) {
                          _highlighterWidth = v;
                        } else {
                          _penWidth = v;
                        }
                      });
                      setSheet(() {});
                    },
                  ),
                  Center(
                    child: Container(
                      width: 200,
                      height: 40,
                      alignment: Alignment.center,
                      child: Container(
                        height: (value / 2).clamp(1, 40).toDouble(),
                        decoration: BoxDecoration(
                          color: isEraser
                              ? AppColors.muted
                              : Color(_color).withValues(alpha: isHl ? 0.4 : 1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _paperSheet(Note note) {
    const names = {
      PaperType.blank: 'Düz',
      PaperType.lined: 'Çizgili',
      PaperType.grid: 'Kareli',
      PaperType.dotted: 'Noktalı',
      PaperType.cornell: 'Cornell',
    };
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kağıt tipi',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in PaperType.values)
                        GestureDetector(
                          onTap: () {
                            note.paper = p;
                            _save(note);
                            setSheet(() {});
                          },
                          child: Container(
                            width: 70,
                            margin: const EdgeInsets.only(right: 10),
                            child: Column(
                              children: [
                                Container(
                                  height: 90,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: note.paper == p
                                          ? AppColors.accent
                                          : AppColors.border,
                                      width: note.paper == p ? 3 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: CustomPaint(
                                    size: const Size(70, 90),
                                    painter: SketchPainter(
                                      strokes: const [],
                                      paper: p,
                                      paperColor: Color(note.paperColor),
                                      pages: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(names[p]!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Kağıt rengi',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final c in _paperColors)
                      GestureDetector(
                        onTap: () {
                          note.paperColor = c;
                          _save(note);
                          setSheet(() {});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: note.paperColor == c ? AppColors.accent : AppColors.border,
                              width: note.paperColor == c ? 3 : 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(Note note) async {
    final name = await promptText(context,
        title: 'Başlık', initial: note.title, hint: 'Ör. Matematik');
    if (name == null) return;
    final old = note.title;
    note.title = name;
    _store.update(note);
    _store.renameLinks(old, name);
  }
}

/// Kement çizgisi ve seçim kutusu (büyütme tutamacıyla).
class _SelectionPainter extends CustomPainter {
  _SelectionPainter({required this.lasso, required this.selection, required this.zoom})
      : super(repaint: lasso);

  final ValueNotifier<List<Offset>> lasso;
  final Rect? selection;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / kPageWidth;
    canvas.save();
    canvas.scale(s);
    final unit = 1 / (s * zoom); // ekranda 1 piksel
    final line = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit;

    final pts = lasso.value;
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, Paint()..color = AppColors.accent.withValues(alpha: 0.08));
      _dashed(canvas, pts, line, 8 * unit);
    }

    final r = selection;
    if (r != null) {
      canvas.drawRect(r, Paint()..color = AppColors.accent.withValues(alpha: 0.07));
      _dashed(canvas, [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft], line, 8 * unit);
      canvas.drawCircle(r.bottomRight, 11 * unit, Paint()..color = AppColors.accent);
      canvas.drawCircle(
        r.bottomRight,
        11 * unit,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * unit,
      );
    }
    canvas.restore();
  }

  void _dashed(Canvas canvas, List<Offset> pts, Paint paint, double dash) {
    var draw = true;
    var left = dash;
    for (var i = 1; i < pts.length; i++) {
      var a = pts[i - 1];
      final b = pts[i];
      var segLen = (b - a).distance;
      if (segLen == 0) continue;
      final dir = (b - a) / segLen;
      while (segLen > 0) {
        final step = min(left, segLen);
        final next = a + dir * step;
        if (draw) canvas.drawLine(a, next, paint);
        a = next;
        segLen -= step;
        left -= step;
        if (left <= 0) {
          draw = !draw;
          left = dash;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.selection != selection || old.zoom != zoom || old.lasso != lasso;
}
