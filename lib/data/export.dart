import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import '../widgets/sketch_painter.dart';
import 'media_cache.dart';
import 'note_store.dart';

String _stamp() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// El yazısı notunu (tüm sayfalarıyla) PNG'ye çevirir.
Future<Uint8List> renderSketchPng(Note n, MediaCache media, {double width = 1200}) async {
  for (final im in n.images) {
    await media.load(im.media);
  }
  final height = width * kPageHeight * n.pages / kPageWidth;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  SketchPainter(
    strokes: n.strokes,
    images: n.images,
    media: media,
    paper: n.paper,
    paperColor: Color(n.paperColor),
    pages: n.pages,
  ).paint(canvas, Size(width, height));
  final image = await recorder.endRecording().toImage(width.round(), height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<File> _tempFile(String name) async {
  final dir = await getTemporaryDirectory();
  return File('${dir.path}/$name');
}

Future<void> _share(File f, String text) =>
    Share.shareXFiles([XFile(f.path)], text: text);

/// Tüm notlar + görseller tek `.sketchmind` dosyasında; paylaşma menüsünü açar
/// (Drive'a, Dosyalar'a ya da başka bir uygulamaya kaydedilebilir).
Future<void> shareBackup(NoteStore store) async {
  final data = await store.exportBackup();
  final f = await _tempFile('sketchmind-yedek-${_stamp()}.sketchmind');
  await f.writeAsString(jsonEncode(data));
  await _share(f, 'Sketchmind yedeği');
}

/// Yedek dosyasını okuyup notları birleştirir. Eklenen not sayısını döner.
Future<int> restoreBackup(NoteStore store, String path) async {
  final raw = jsonDecode(await File(path).readAsString());
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Dosya okunamadı.');
  }
  return store.importBackup(raw);
}

String _safeName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), '-').trim();
  return cleaned.isEmpty ? 'Başlıksız Not' : cleaned;
}

/// Obsidian'da açılabilecek bir klasör yapısı: metin notları `.md`,
/// el yazısı notları `.png`. `![[Çizim]]` gömmeleri `![[Çizim.png]]` olur.
Future<void> shareMarkdownZip(NoteStore store, MediaCache media) async {
  final notes = store.notes;
  final archive = Archive();
  final usedPaths = <String>{};
  final sketchFile = <String, String>{}; // küçük harf başlık → dosya adı

  String uniquePath(String folder, String base, String ext) {
    final dir = folder.isEmpty ? '' : '${_safeName(folder)}/';
    var name = base;
    var i = 2;
    while (usedPaths.contains('$dir$name.$ext'.toLowerCase())) {
      name = '$base ($i)';
      i++;
    }
    usedPaths.add('$dir$name.$ext'.toLowerCase());
    return '$dir$name.$ext';
  }

  for (final n in notes.where((n) => n.type == NoteType.sketch)) {
    final path = uniquePath(n.folder, _safeName(n.displayTitle), 'png');
    final png = await renderSketchPng(n, media);
    archive.addFile(ArchiveFile(path, png.length, png));
    if (!n.isUntitled) sketchFile[n.title.trim().toLowerCase()] = path.split('/').last;
  }

  for (final n in notes.where((n) => n.type == NoteType.text)) {
    final path = uniquePath(n.folder, _safeName(n.displayTitle), 'md');
    final body = n.content.replaceAllMapped(linkRegex, (m) {
      final file = sketchFile[m.group(1)!.trim().toLowerCase()];
      if (file == null) return m.group(0)!;
      final alias = m.group(2);
      return alias == null ? '[[$file]]' : '[[$file|$alias]]';
    });
    final bytes = utf8.encode(body);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) throw StateError('Zip oluşturulamadı');
  final f = await _tempFile('sketchmind-markdown-${_stamp()}.zip');
  await f.writeAsBytes(zipped);
  await _share(f, 'Sketchmind notları (Markdown)');
}
