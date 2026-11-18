import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchmind/data/note_store.dart';
import 'package:sketchmind/models/note.dart';

void main() {
  test('Not JSON gidiş-dönüş', () {
    final n = Note(
      id: 'a',
      type: NoteType.sketch,
      title: 'Çizim',
      strokes: const [
        Stroke(points: [Offset(1, 2), Offset(3.25, 4)], color: 0xFFFF0000, width: 5),
      ],
      paper: PaperType.cornell,
      favorite: true,
    );
    final back = Note.fromJson(n.toJson());
    expect(back.title, 'Çizim');
    expect(back.type, NoteType.sketch);
    expect(back.paper, PaperType.cornell);
    expect(back.favorite, isTrue);
    expect(back.strokes.single.points.last, const Offset(3.3, 4));
  });

  test('Bağlantı ve etiket ayrıştırma', () {
    final n = Note(
      id: 'b',
      type: NoteType.text,
      content: '# Başlık\n[[Kısayollar]] ve [[Fikirler|fikir]] [[Ders#Bölüm]] #ödev #2024 a#b `[[Örnek]] #kod`',
    );
    expect(n.links, ['Kısayollar', 'Fikirler', 'Ders']);
    expect(n.tags, {'ödev'});
  });

  test('Yeniden adlandırmada bağlantılar güncellenir', () async {
    final dir = await Directory.systemTemp.createTemp('sketchmind');
    final store = NoteStore(directoryOverride: dir);
    await store.load(); // örnek notlar oluşur
    final kisayol = store.byTitle('Kısayollar')!;
    kisayol.title = 'İpuçları';
    store.renameLinks('Kısayollar', 'İpuçları');
    final welcome = store.byTitle("Sketchmind'a hoş geldin")!;
    expect(welcome.content.contains('[[İpuçları]]'), isTrue);
    expect(store.backlinks(kisayol).map((n) => n.id), contains(welcome.id));
    await store.flush();
    await dir.delete(recursive: true);
  });

  test('Silgi çizgiye yakın noktayı yakalar', () {
    const s = Stroke(points: [Offset(0, 0), Offset(100, 0)], color: 0, width: 4);
    expect(s.hits(const Offset(50, 10), 10), isTrue);
    expect(s.hits(const Offset(50, 40), 10), isFalse);
  });

  test('Çöp kutusu: taşı, geri yükle, kalıcı sil', () async {
    final dir = await Directory.systemTemp.createTemp('sketchmind');
    final store = NoteStore(directoryOverride: dir);
    await store.load();
    final n = store.byTitle('Kısayollar')!;
    final total = store.notes.length;
    store.moveToTrash(n);
    expect(store.notes.length, total - 1);
    expect(store.trash.single.id, n.id);
    expect(store.byTitle('Kısayollar'), isNull);
    expect(n.daysLeftInTrash, 30);
    store.restore(n);
    expect(store.trash, isEmpty);
    store.moveToTrash(n);
    await store.deleteForever(n);
    expect(store.trash, isEmpty);
    expect(store.notes.length, total - 1);
    await store.flush();
    await dir.delete(recursive: true);
  });

  test('PIN ve yedek', () async {
    final dir = await Directory.systemTemp.createTemp('sketchmind');
    final store = NoteStore(directoryOverride: dir);
    await store.load();
    store.setPin('1234');
    expect(store.checkPin('1234'), isTrue);
    expect(store.checkPin('0000'), isFalse);
    final backup = await store.exportBackup();
    expect(backup.containsKey('security'), isFalse);

    final dir2 = await Directory.systemTemp.createTemp('sketchmind');
    final other = NoteStore(directoryOverride: dir2);
    await other.load();
    final before = other.notes.length;
    final count = await other.importBackup(backup);
    expect(count, store.notes.length);
    // Örnek notların kimlikleri farklı olduğu için eklenir.
    expect(other.notes.length, before + count);
    await store.flush();
    await other.flush();
    await dir.delete(recursive: true);
    await dir2.delete(recursive: true);
  });
}
