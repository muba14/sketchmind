import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';

enum SortMode { updated, created, title }

/// Tüm notları tutan, değişince arayüzü haberdar eden ve diske kaydeden depo.
class NoteStore extends ChangeNotifier {
  NoteStore({this.directoryOverride});

  /// Testlerde path_provider yerine kullanılacak klasör.
  final Directory? directoryOverride;

  /// Çöp kutusundakiler dahil tüm notlar.
  final List<Note> _all = [];
  final List<String> _folders = [];
  final List<String> _openTabs = [];
  SortMode sortMode = SortMode.updated;
  bool loaded = false;

  // Kilit ayarları
  String? _pinHash;
  String _pinSalt = '';
  bool useBiometrics = true;
  bool _sessionUnlocked = false;

  Directory? _dir;
  File? _file;
  Timer? _saveTimer;

  /// Çöp kutusunda olmayan notlar.
  List<Note> get notes => List.unmodifiable(_all.where((n) => !n.isTrashed));

  /// Çöp kutusu, en son silinen önce.
  List<Note> get trash {
    final t = _all.where((n) => n.isTrashed).toList();
    t.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return t;
  }

  Directory get mediaDir => Directory('${_dir!.path}/sketchmind_media');
  File mediaFile(String name) => File('${mediaDir.path}/$name');

  // ---------------------------------------------------------------- yükleme
  Future<void> load() async {
    try {
      _dir = directoryOverride ?? await getApplicationDocumentsDirectory();
      await mediaDir.create(recursive: true);
      _file = File('${_dir!.path}/sketchmind_notes.json');
      if (await _file!.exists()) {
        _applyJson(jsonDecode(await _file!.readAsString()) as Map<String, dynamic>);
        await _purgeExpiredTrash();
      } else {
        _seed();
        _scheduleSave();
      }
    } catch (e) {
      debugPrint('Notlar yüklenemedi: $e');
      // Bozuk dosyayı yedekle, yeniden başla.
      try {
        if (_file != null && await _file!.exists()) {
          await _file!.copy('${_file!.path}.bak');
        }
      } catch (_) {}
      if (_all.isEmpty) _seed();
    }
    loaded = true;
    notifyListeners();
  }

  void _applyJson(Map<String, dynamic> raw) {
    _all
      ..clear()
      ..addAll([
        for (final n in (raw['notes'] as List? ?? const []))
          Note.fromJson((n as Map).cast<String, dynamic>()),
      ]);
    _folders
      ..clear()
      ..addAll((raw['folders'] as List? ?? const []).cast<String>());
    _openTabs
      ..clear()
      ..addAll((raw['tabs'] as List? ?? const []).cast<String>().where((id) => byId(id) != null));
    sortMode = SortMode.values.firstWhere(
      (m) => m.name == raw['sort'],
      orElse: () => SortMode.updated,
    );
    final sec = (raw['security'] as Map?)?.cast<String, dynamic>();
    _pinHash = sec?['pinHash'] as String?;
    _pinSalt = sec?['salt'] as String? ?? '';
    useBiometrics = sec?['biometrics'] as bool? ?? true;
  }

  Map<String, dynamic> _toJson() => {
        'version': 2,
        'sort': sortMode.name,
        'folders': _folders,
        'tabs': _openTabs,
        'security': {
          if (_pinHash != null) 'pinHash': _pinHash,
          'salt': _pinSalt,
          'biometrics': useBiometrics,
        },
        'notes': [for (final n in _all) n.toJson()],
      };

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    final file = _file;
    if (file == null) return;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_toJson()), flush: true);
    await tmp.rename(file.path);
  }

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  // ---------------------------------------------------------------- sorgular
  /// Çöp kutusunda olmayan not.
  Note? byId(String id) {
    for (final n in _all) {
      if (n.id == id && !n.isTrashed) return n;
    }
    return null;
  }

  Note? byTitle(String title) {
    final t = title.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final n in _all) {
      if (!n.isTrashed && n.title.trim().toLowerCase() == t) return n;
    }
    return null;
  }

  bool titleExists(String title) => byTitle(title) != null;

  List<Note> sorted(Iterable<Note> list) {
    final out = list.toList();
    out.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return switch (sortMode) {
        SortMode.updated => b.updated.compareTo(a.updated),
        SortMode.created => b.created.compareTo(a.created),
        SortMode.title =>
          a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
      };
    });
    return out;
  }

  /// Bu nota `[[başlık]]` ya da `![[başlık]]` ile bağlanan notlar.
  List<Note> backlinks(Note note) {
    if (note.isUntitled) return const [];
    final t = note.title.trim().toLowerCase();
    return [
      for (final n in notes)
        if (n.id != note.id && n.links.any((l) => l.toLowerCase() == t)) n,
    ];
  }

  List<String> get folders {
    final names = <String>{..._folders};
    for (final n in notes) {
      if (n.folder.isNotEmpty) names.add(n.folder);
    }
    final list = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Map<String, int> get tagCounts {
    final map = <String, int>{};
    for (final n in notes) {
      if (n.locked) continue;
      for (final t in n.tags) {
        map[t] = (map[t] ?? 0) + 1;
      }
    }
    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  /// Kilitli notların içeriği aramada görünmez, sadece başlığı aranır.
  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = notes
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            (!n.locked && n.content.toLowerCase().contains(q)))
        .toList();
    hits.sort((a, b) {
      final at = a.title.toLowerCase().contains(q) ? 0 : 1;
      final bt = b.title.toLowerCase().contains(q) ? 0 : 1;
      if (at != bt) return at - bt;
      return b.updated.compareTo(a.updated);
    });
    return hits;
  }

  // ---------------------------------------------------------------- değişiklikler
  Note createText({String title = '', String content = '', String folder = ''}) {
    final n = Note(
      id: Note.newId(),
      type: NoteType.text,
      title: title,
      content: content,
      folder: folder,
    );
    _all.add(n);
    _changed();
    return n;
  }

  Note createSketch({String title = '', String folder = ''}) {
    final n = Note(
      id: Note.newId(),
      type: NoteType.sketch,
      title: title,
      folder: folder,
      paper: PaperType.grid,
      paperColor: 0xFF1F1F27,
    );
    _all.add(n);
    _changed();
    return n;
  }

  void update(Note note, {bool touch = true}) {
    if (touch) note.updated = DateTime.now();
    _changed();
  }

  Note duplicate(Note note) {
    final copy = note.duplicate();
    _all.add(copy);
    _changed();
    return copy;
  }

  // ---------------------------------------------------------------- çöp kutusu
  /// Notu çöp kutusuna taşır (30 gün sonra kalıcı silinir).
  void moveToTrash(Note note) {
    note.deletedAt = DateTime.now();
    note.pinned = false;
    _openTabs.remove(note.id);
    _changed();
  }

  void restore(Note note) {
    note.deletedAt = null;
    // Aynı başlıkta yeni bir not açılmışsa karışmasın.
    if (!note.isUntitled && _all.any((n) => n != note && !n.isTrashed &&
        n.title.trim().toLowerCase() == note.title.trim().toLowerCase())) {
      note.title = '${note.title.trim()} (geri yüklendi)';
    }
    _changed();
  }

  Future<void> deleteForever(Note note) async {
    _all.removeWhere((n) => n.id == note.id);
    _openTabs.remove(note.id);
    _changed();
    await _cleanUnusedMedia();
  }

  Future<void> emptyTrash() async {
    _all.removeWhere((n) => n.isTrashed);
    _changed();
    await _cleanUnusedMedia();
  }

  Future<void> _purgeExpiredTrash() async {
    final now = DateTime.now();
    final before = _all.length;
    _all.removeWhere((n) => n.deletedAt != null && now.difference(n.deletedAt!) > kTrashRetention);
    if (_all.length != before) {
      _scheduleSave();
      await _cleanUnusedMedia();
    }
  }

  Future<void> _cleanUnusedMedia() async {
    if (_dir == null) return;
    final used = {for (final n in _all) ...n.mediaFiles};
    try {
      await for (final f in mediaDir.list()) {
        final name = f.uri.pathSegments.last;
        if (f is File && !used.contains(name)) await f.delete();
      }
    } catch (e) {
      debugPrint('Medya temizlenemedi: $e');
    }
  }

  // ---------------------------------------------------------------- medya
  /// Görsel baytlarını medya klasörüne yazar, dosya adını döner.
  Future<String> saveMedia(Uint8List bytes, String ext) async {
    final name = '${Note.newId()}.$ext';
    await mediaFile(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  // ---------------------------------------------------------------- kilit
  bool get hasPin => _pinHash != null;
  bool get sessionUnlocked => _sessionUnlocked;

  String _hash(String pin) => sha256.convert(utf8.encode('$_pinSalt:$pin')).toString();

  void setPin(String pin) {
    final r = Random.secure();
    _pinSalt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    _pinHash = _hash(pin);
    _sessionUnlocked = true;
    _changed();
  }

  bool checkPin(String pin) => _pinHash != null && _hash(pin) == _pinHash;

  void unlockSession() {
    _sessionUnlocked = true;
    notifyListeners();
  }

  /// Uygulama arka plana geçince kilitli notlar yeniden kilitlenir.
  void lockSession() {
    if (!_sessionUnlocked) return;
    _sessionUnlocked = false;
    notifyListeners();
  }

  void setBiometrics(bool v) {
    useBiometrics = v;
    _changed();
  }

  /// Kilitli notlar varsa PIN kaldırılamaz.
  bool removePin() {
    if (_all.any((n) => n.locked)) return false;
    _pinHash = null;
    _changed();
    return true;
  }

  // ---------------------------------------------------------------- yedek
  /// Tüm notlar + medya dosyaları tek JSON nesnesinde (base64).
  Future<Map<String, dynamic>> exportBackup() async {
    final media = <String, String>{};
    for (final n in _all) {
      for (final m in n.mediaFiles) {
        final f = mediaFile(m);
        if (!media.containsKey(m) && await f.exists()) {
          media[m] = base64Encode(await f.readAsBytes());
        }
      }
    }
    final data = _toJson();
    data.remove('security'); // PIN yedekle taşınmaz
    return {
      'app': 'sketchmind',
      'exported': DateTime.now().toIso8601String(),
      ...data,
      'media': media,
    };
  }

  /// Yedeği birleştirir: aynı kimlikli notların yedekteki hali kullanılır.
  /// Eklenen/güncellenen not sayısını döner.
  Future<int> importBackup(Map<String, dynamic> raw) async {
    if (raw['app'] != 'sketchmind') {
      throw const FormatException('Bu dosya bir Sketchmind yedeği değil.');
    }
    final media = (raw['media'] as Map? ?? const {}).cast<String, dynamic>();
    for (final e in media.entries) {
      final f = mediaFile(e.key);
      if (!await f.exists()) await f.writeAsBytes(base64Decode(e.value as String));
    }
    var count = 0;
    for (final j in (raw['notes'] as List? ?? const [])) {
      final n = Note.fromJson((j as Map).cast<String, dynamic>());
      _all.removeWhere((x) => x.id == n.id);
      _all.add(n);
      count++;
    }
    for (final f in (raw['folders'] as List? ?? const []).cast<String>()) {
      if (!_folders.contains(f)) _folders.add(f);
    }
    _changed();
    return count;
  }

  void addFolder(String name) {
    final f = name.trim();
    if (f.isEmpty || _folders.contains(f)) return;
    _folders.add(f);
    _changed();
  }

  void deleteFolder(String name) {
    _folders.remove(name);
    for (final n in _all) {
      if (n.folder == name) n.folder = '';
    }
    _changed();
  }

  void setSort(SortMode mode) {
    sortMode = mode;
    _changed();
  }

  /// Başlık değişince diğer notlardaki `[[eski]]` bağlantılarını günceller.
  void renameLinks(String oldTitle, String newTitle) {
    final o = oldTitle.trim();
    final nw = newTitle.trim();
    if (o.isEmpty || nw.isEmpty || o.toLowerCase() == nw.toLowerCase()) return;
    var changed = false;
    for (final n in _all) {
      if (n.type != NoteType.text) continue;
      final updated = n.content.replaceAllMapped(linkRegex, (m) {
        if (m.group(1)!.trim().toLowerCase() != o.toLowerCase()) return m.group(0)!;
        // Sadece hedef kısmını değiştir, #başlık ve |takma ad kalsın.
        return m.group(0)!.replaceFirst(m.group(1)!, nw);
      });
      if (updated != n.content) {
        n.content = updated;
        changed = true;
      }
    }
    if (changed) _changed();
  }

  // ---------------------------------------------------------------- sekmeler
  List<Note> get openTabs => [
        for (final id in _openTabs)
          if (byId(id) != null) byId(id)!,
      ];

  String? get activeTabId => _openTabs.isEmpty ? null : _openTabs.last;

  void openTab(String id) {
    _openTabs.remove(id);
    _openTabs.add(id);
    if (_openTabs.length > 30) _openTabs.removeAt(0);
    _changed();
  }

  void closeTab(String id) {
    _openTabs.remove(id);
    _changed();
  }

  void closeAllTabs() {
    _openTabs.clear();
    _changed();
  }

  // ---------------------------------------------------------------- ilk açılış
  void _seed() {
    final now = DateTime.now();
    _all.addAll([
      Note(
        id: Note.newId(),
        type: NoteType.text,
        title: "Sketchmind'a hoş geldin",
        pinned: true,
        updated: now,
        content: '''# Sketchmind'a hoş geldin 👋
Obsidian gibi **bağlantılı notlar**, Squid gibi **el yazısı sayfaları**.

Günlük ----------------------------------------
- [x] Sketchmind'ı kur
- [ ] İlk notunu oluştur
- [ ] Bir el yazısı sayfası aç
----------------------------------------

## Bağlantılar
Başka bir nota bağlanmak için [[Kısayollar]] gibi çift köşeli parantez kullan.
El yazısı sayfasını notun içine gömebilirsin:
![[Matematik]]
Henüz olmayan bir nota verilen bağlantıya dokununca not oluşturulur: [[Fikirler]]

## Biçimlendirme
==Vurgulu metin==, ~~üstü çizili~~, *italik*, `satır içi kod` ve #rehber etiketi.

> Grafik sekmesinden notların birbirine nasıl bağlandığını görebilirsin.
''',
      ),
      Note(
        id: Note.newId(),
        type: NoteType.text,
        title: 'Kısayollar',
        folder: 'Rehber',
        updated: now.subtract(const Duration(minutes: 5)),
        content: '''# Kısayollar
Yazma modunda klavyenin üstündeki araç çubuğunu kullanabilirsin.

- `- [ ] görev` → yapılacak kutusu
- `# Başlık` → başlık
- `**kalın**`, `*italik*`, `~~çizili~~`
- `==vurgu==` → sarı vurgulama
- `[[Not adı]]` → bağlantı
- `#etiket` → etiket
- `---` → ayırıcı çizgi

```
Kod blokları üç ters tırnakla yazılır.
```

Geri dön: [[Sketchmind'a hoş geldin]] #rehber
''',
      ),
      Note(
        id: Note.newId(),
        type: NoteType.sketch,
        title: 'Matematik',
        folder: 'Dersler',
        paper: PaperType.cornell,
        paperColor: 0xFFFFFFFF,
        updated: now.subtract(const Duration(minutes: 10)),
        strokes: _demoStrokes(),
      ),
    ]);
    _folders.addAll(['Dersler', 'Rehber']);
  }

  static List<Stroke> _demoStrokes() {
    const orange = 0xFFFF6B35;
    const blue = 0xFF3E8BFF;
    final wave = <Offset>[
      for (var x = 0; x <= 600; x += 6)
        Offset(340 + x.toDouble(), 620 - sin(x / 600 * 4 * pi) * 120),
    ];
    return [
      const Stroke(points: [Offset(320, 620), Offset(960, 620)], color: blue, width: 4),
      const Stroke(points: [Offset(340, 440), Offset(340, 800)], color: blue, width: 4),
      Stroke(points: wave, color: orange, width: 7),
      // "sin x"
      const Stroke(
        points: [Offset(400, 330), Offset(380, 315), Offset(360, 330), Offset(380, 350), Offset(400, 365), Offset(380, 380), Offset(358, 368)],
        color: orange,
        width: 6,
      ),
      const Stroke(points: [Offset(425, 330), Offset(425, 380)], color: orange, width: 6),
      const Stroke(points: [Offset(425, 305), Offset(426, 308)], color: orange, width: 8),
      const Stroke(
        points: [Offset(455, 380), Offset(455, 330), Offset(470, 320), Offset(490, 330), Offset(492, 380)],
        color: orange,
        width: 6,
      ),
      const Stroke(points: [Offset(530, 325), Offset(575, 380)], color: orange, width: 6),
      const Stroke(points: [Offset(575, 325), Offset(530, 380)], color: orange, width: 6),
    ];
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
