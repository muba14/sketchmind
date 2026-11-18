import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'note_store.dart';

/// Sayfalara eklenen fotoğraf/PDF görsellerini çözüp bellekte tutar.
/// Bir görsel yüklenince dinleyicileri (çizim katmanlarını) yeniden çizdirir.
class MediaCache extends ChangeNotifier {
  MediaCache(this.store);

  final NoteStore store;
  final Map<String, ui.Image> _images = {};
  final Set<String> _loading = {};

  /// Yüklüyse görseli döner; değilse yüklemeyi başlatır ve null döner.
  ui.Image? get(String name) {
    final img = _images[name];
    if (img != null) return img;
    if (_loading.add(name)) _load(name);
    return null;
  }

  /// Görsel yüklenene kadar bekler (dışa aktarırken).
  Future<ui.Image?> load(String name) async {
    if (_images[name] == null) await _load(name);
    return _images[name];
  }

  Future<void> _load(String name) async {
    try {
      final bytes = await store.mediaFile(name).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) =>
            w > 1800 ? ui.TargetImageSize(width: 1800) : ui.TargetImageSize(),
      );
      final frame = await codec.getNextFrame();
      _images[name]?.dispose();
      _images[name] = frame.image;
      notifyListeners();
    } catch (e) {
      debugPrint('Görsel yüklenemedi ($name): $e');
    }
  }

  @override
  void dispose() {
    for (final img in _images.values) {
      img.dispose();
    }
    super.dispose();
  }
}
