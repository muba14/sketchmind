import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sketchmind/models/note.dart';
import 'package:sketchmind/theme.dart';
import 'package:sketchmind/widgets/markdown_view.dart';

void main() {
  testWidgets('Görev kutusuna dokununca işaretlenir', (tester) async {
    String? changed;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: MarkdownView(
          source: '# Yapılacaklar\n- [ ] kitap oku\n==vurgu== [[Bağlantı]] #etiket',
          onChanged: (s) => changed = s,
        ),
      ),
    ));
    expect(find.text('Yapılacaklar'), findsOneWidget);
    await tester.tap(find
        .descendant(of: find.byType(MarkdownView), matching: find.byType(GestureDetector))
        .first);
    expect(changed, contains('- [x] kitap oku'));
  });

  test('Tarih biçimi', () {
    expect(formatDate(DateTime(2026, 11, 17)), '17 Kas 2026');
    expect(Note(id: 'x', type: NoteType.text).displayTitle, 'Başlıksız Not');
  });
}
