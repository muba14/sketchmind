import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sketchmind/models/note.dart';
import 'package:sketchmind/sketch/shape_recognizer.dart';

Stroke _s(List<Offset> pts) => Stroke(points: pts, color: 0xFF000000, width: 4);

/// Hafif titrek el çizimi taklidi (rastgele değil, her çalıştırmada aynı).
List<Offset> _wobble(List<Offset> pts, {double amp = 3}) => [
      for (var i = 0; i < pts.length; i++)
        pts[i] + Offset(sin(i * 1.7) * amp / 2, cos(i * 2.3) * amp / 2),
    ];

List<Offset> _seg(Offset a, Offset b, [int n = 20]) =>
    [for (var i = 0; i < n; i++) Offset.lerp(a, b, i / n)!];

void main() {
  test('Düz çizgi', () {
    final out = recognizeShape(_s(_wobble(_seg(const Offset(0, 0), const Offset(300, 40), 40))));
    expect(out, isNotNull);
    expect(out!.points.length, 2);
    expect(out.shape, isTrue);
  });

  test('Dikdörtgen', () {
    const a = Offset(100, 100), b = Offset(400, 100), c = Offset(400, 300), d = Offset(100, 300);
    final pts = _wobble([..._seg(a, b), ..._seg(b, c), ..._seg(c, d), ..._seg(d, a), a]);
    final out = recognizeShape(_s(pts));
    expect(out, isNotNull);
    expect(out!.points.length, 5); // kapalı dikdörtgen
  });

  test('Üçgen', () {
    const a = Offset(200, 100), b = Offset(350, 350), c = Offset(50, 350);
    final pts = _wobble([..._seg(a, b), ..._seg(b, c), ..._seg(c, a), a]);
    final out = recognizeShape(_s(pts));
    expect(out, isNotNull);
    expect(out!.points.length, 4);
  });

  test('Daire', () {
    final pts = _wobble([
      for (var i = 0; i <= 60; i++) Offset(300 + 120 * cos(i / 60 * 2 * pi), 300 + 115 * sin(i / 60 * 2 * pi)),
    ], amp: 6);
    final out = recognizeShape(_s(pts));
    expect(out, isNotNull);
    expect(out!.points.length, greaterThan(40));
  });

  test('Ok', () {
    const a = Offset(50, 300), tip = Offset(400, 300);
    final pts = [..._seg(a, tip, 40), ..._seg(tip, const Offset(360, 270), 6)];
    final out = recognizeShape(_s(pts));
    expect(out, isNotNull);
    expect(out!.points.length, 5);
    expect(out.points[1], tip);
  });

  test('Karalama tanınmaz', () {
    // Zikzak karalama
    final pts = [for (var i = 0; i < 60; i++) Offset(i * 5.0, (i * 37 % 11) * 25.0)];
    expect(recognizeShape(_s(pts)), isNull);
  });

  test('El yazısı harfi tanınmaz', () {
    final pts = [for (var i = 0; i < 50; i++) Offset(100 + 60 * sin(i / 49 * 2 * pi), 100 + i / 49 * 150)];
    expect(recognizeShape(_s(pts)), isNull);
  });

  test('Kement: nokta çokgende mi', () {
    const poly = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];
    expect(pointInPolygon(const Offset(50, 50), poly), isTrue);
    expect(pointInPolygon(const Offset(150, 50), poly), isFalse);
  });
}
