import 'dart:math';
import 'dart:ui';

enum NoteType { text, sketch }

enum PaperType { blank, lined, grid, dotted, cornell }

/// Bir el yazısı sayfasının mantıksal boyutu (A4 oranı).
/// Çizgiler bu koordinatlarda saklanır, ekrana ölçeklenerek çizilir.
const double kPageWidth = 1000;
const double kPageHeight = 1414;

/// Çöp kutusundaki notların kalıcı silinmeden önce bekleme süresi.
const Duration kTrashRetention = Duration(days: 30);

/// `[[Hedef]]`, `[[Hedef|Takma ad]]`, `[[Hedef#Başlık]]`
final RegExp linkRegex = RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]');

/// Tek başına bir satırda duran gömme: `![[Matematik]]`
final RegExp embedLineRegex = RegExp(r'^\s*!\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]+))?\]\]\s*$');

/// `#etiket` (başlıklardaki "# " ile karışmaz).
final RegExp tagRegex =
    RegExp(r'(?:^|\s)#([\p{L}_][\p{L}\p{N}_/-]*)', unicode: true);

class Stroke {
  final List<Offset> points;
  final int color;
  final double width;
  final bool highlighter;

  /// Şekil düzeltmeyle oluşan çizgi: köşeler yumuşatılmadan düz çizilir.
  final bool shape;

  const Stroke({
    required this.points,
    required this.color,
    required this.width,
    this.highlighter = false,
    this.shape = false,
  });

  Stroke copyWith({List<Offset>? points, double? width}) => Stroke(
        points: points ?? this.points,
        color: color,
        width: width ?? this.width,
        highlighter: highlighter,
        shape: shape,
      );

  /// Tüm noktalara dönüşüm uygular (kement ile taşıma/büyütme).
  Stroke transformed(Offset Function(Offset) f, {double widthScale = 1}) => copyWith(
        points: [for (final p in points) f(p)],
        width: (width * widthScale).clamp(1.0, 200.0).toDouble(),
      );

  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      minX = min(minX, p.dx);
      maxX = max(maxX, p.dx);
      minY = min(minY, p.dy);
      maxY = max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(width / 2);
  }

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        if (highlighter) 'h': true,
        if (shape) 's': true,
        'p': [
          for (final p in points) ...[
            (p.dx * 10).round() / 10,
            (p.dy * 10).round() / 10,
          ],
        ],
      };

  factory Stroke.fromJson(Map<String, dynamic> j) {
    final raw = (j['p'] as List).cast<num>();
    final pts = <Offset>[];
    for (var i = 0; i + 1 < raw.length; i += 2) {
      pts.add(Offset(raw[i].toDouble(), raw[i + 1].toDouble()));
    }
    return Stroke(
      points: pts,
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      highlighter: j['h'] == true,
      shape: j['s'] == true,
    );
  }

  /// Nokta, çizgiye [radius] kadar yakın mı? (silgi için)
  bool hits(Offset p, double radius) {
    final r2 = (radius + width / 2) * (radius + width / 2);
    for (var i = 0; i < points.length; i++) {
      if ((points[i] - p).distanceSquared <= r2) return true;
      if (i > 0 && segmentDistance2(p, points[i - 1], points[i]) <= r2) return true;
    }
    return false;
  }

  static double segmentDistance2(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    if (len2 == 0) return (p - a).distanceSquared;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0).toDouble();
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distanceSquared;
  }
}

/// Sayfaya eklenmiş fotoğraf ya da PDF sayfası. Görsel dosyası
/// uygulama klasöründeki medya dizininde [media] adıyla durur.
class SketchImage {
  final String id;
  final String media;
  final Rect rect;

  /// PDF'ten gelen sayfa arka planı (kement onu seçmez, yanlışlıkla kaymasın).
  final bool background;

  const SketchImage({
    required this.id,
    required this.media,
    required this.rect,
    this.background = false,
  });

  SketchImage withRect(Rect r) =>
      SketchImage(id: id, media: media, rect: r, background: background);

  Map<String, dynamic> toJson() => {
        'id': id,
        'm': media,
        'r': [rect.left, rect.top, rect.width, rect.height],
        if (background) 'bg': true,
      };

  factory SketchImage.fromJson(Map<String, dynamic> j) {
    final r = (j['r'] as List).cast<num>();
    return SketchImage(
      id: j['id'] as String,
      media: j['m'] as String,
      rect: Rect.fromLTWH(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
      background: j['bg'] == true,
    );
  }
}

class Note {
  final String id;
  NoteType type;
  String title;
  String content;
  List<Stroke> strokes;
  List<SketchImage> images;
  PaperType paper;
  int paperColor;
  int pages;
  String folder;
  bool favorite;
  bool pinned;
  bool locked;
  DateTime created;
  DateTime updated;

  /// Doluysa not çöp kutusundadır.
  DateTime? deletedAt;

  Note({
    required this.id,
    required this.type,
    this.title = '',
    this.content = '',
    List<Stroke>? strokes,
    List<SketchImage>? images,
    this.paper = PaperType.grid,
    this.paperColor = 0xFF1F1F27,
    this.pages = 1,
    this.folder = '',
    this.favorite = false,
    this.pinned = false,
    this.locked = false,
    DateTime? created,
    DateTime? updated,
    this.deletedAt,
  })  : strokes = strokes ?? [],
        images = images ?? [],
        created = created ?? DateTime.now(),
        updated = updated ?? DateTime.now();

  static final _rand = Random();
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  bool get isUntitled => title.trim().isEmpty;
  String get displayTitle => isUntitled ? 'Başlıksız Not' : title.trim();
  bool get isTrashed => deletedAt != null;

  /// Çöp kutusunda kalan gün sayısı.
  int get daysLeftInTrash {
    final d = deletedAt;
    if (d == null) return 0;
    final left = d.add(kTrashRetention).difference(DateTime.now()).inHours / 24;
    return max(0, left.ceil());
  }

  static final _codeBlock = RegExp(r'```[\s\S]*?```');
  static final _inlineCode = RegExp(r'`[^`\n]*`');

  /// Kod blokları ve satır içi kod hariç metin (örnek `[[bağlantı]]`lar sayılmasın).
  String get _textWithoutCode =>
      content.replaceAll(_codeBlock, '').replaceAll(_inlineCode, '');

  /// Bu notun verdiği bağlantıların (ve gömmelerin) hedef başlıkları.
  List<String> get links {
    if (type != NoteType.text) return const [];
    final out = <String>[];
    for (final m in linkRegex.allMatches(_textWithoutCode)) {
      final t = m.group(1)!.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out;
  }

  Set<String> get tags {
    if (type != NoteType.text) return const {};
    return {
      for (final m in tagRegex.allMatches(_textWithoutCode)) m.group(1)!.toLowerCase(),
    };
  }

  /// Bu notun kullandığı medya dosyaları.
  Set<String> get mediaFiles => {for (final i in images) i.media};

  Note duplicate() => Note(
        id: newId(),
        type: type,
        title: isUntitled ? '' : '$title (kopya)',
        content: content,
        strokes: List.of(strokes),
        images: List.of(images),
        paper: paper,
        paperColor: paperColor,
        pages: pages,
        folder: folder,
        locked: locked,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'content': content,
        'strokes': [for (final s in strokes) s.toJson()],
        if (images.isNotEmpty) 'images': [for (final i in images) i.toJson()],
        'paper': paper.name,
        'paperColor': paperColor,
        'pages': pages,
        'folder': folder,
        'favorite': favorite,
        'pinned': pinned,
        if (locked) 'locked': true,
        'created': created.toIso8601String(),
        'updated': updated.toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        type: NoteType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => NoteType.text,
        ),
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        strokes: [
          for (final s in (j['strokes'] as List? ?? const []))
            Stroke.fromJson((s as Map).cast<String, dynamic>()),
        ],
        images: [
          for (final i in (j['images'] as List? ?? const []))
            SketchImage.fromJson((i as Map).cast<String, dynamic>()),
        ],
        paper: PaperType.values.firstWhere(
          (p) => p.name == j['paper'],
          orElse: () => PaperType.blank,
        ),
        paperColor: j['paperColor'] as int? ?? 0xFFFFFFFF,
        pages: j['pages'] as int? ?? 1,
        folder: j['folder'] as String? ?? '',
        favorite: j['favorite'] == true,
        pinned: j['pinned'] == true,
        locked: j['locked'] == true,
        created: DateTime.tryParse(j['created'] as String? ?? ''),
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
        deletedAt: DateTime.tryParse(j['deletedAt'] as String? ?? ''),
      );
}
