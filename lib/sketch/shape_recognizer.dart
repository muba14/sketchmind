import 'dart:math';
import 'dart:ui';

import '../models/note.dart';

/// Elle çizilmiş bir çizgiyi düzgün şekle çevirmeye çalışır:
/// düz çizgi, ok, üçgen, dikdörtgen ve daire/elips.
/// Tanınmazsa `null` döner.
///
/// Kullanım: kullanıcı çizginin sonunda kalemi bir an sabit tutunca çağrılır.
Stroke? recognizeShape(Stroke s) {
  final pts = s.points;
  if (pts.length < 4) return null;
  final box = _bounds(pts);
  final diag = sqrt(box.width * box.width + box.height * box.height);
  if (diag < 30) return null;

  final closed = (pts.first - pts.last).distance < max(diag * 0.22, 25);
  final result = closed ? _closedShape(pts, box, diag) : _openShape(pts);
  if (result == null) return null;
  return Stroke(
    points: result,
    color: s.color,
    width: s.width,
    highlighter: s.highlighter,
    shape: true,
  );
}

// ------------------------------------------------------------------ açık şekiller
List<Offset>? _openShape(List<Offset> pts) {
  final a = pts.first, e = pts.last;
  final len = (e - a).distance;

  // Düz çizgi: tüm noktalar baştan sona çizilen doğruya yakın.
  if (len > 20 && _maxDeviation(pts, a, e) < max(len * 0.07, 8)) {
    return [a, e];
  }

  // Ok: baştan en uzak noktaya kadar düz, sonra kısa bir "uç" kıvrımı.
  var k = 0;
  var far = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final d = (pts[i] - a).distance;
    if (d > far) {
      far = d;
      k = i;
    }
  }
  if (far < 40 || k >= pts.length - 2) return null;
  final tip = pts[k];
  final shaft = pts.sublist(0, k + 1);
  if (_maxDeviation(shaft, a, tip) > max(far * 0.08, 10)) return null;
  final tail = _pathLength(pts.sublist(k));
  if (tail < far * 0.08 || tail > far * 0.6) return null;

  final dir = (tip - a) / far;
  final head = (far * 0.22).clamp(18.0, 70.0).toDouble();
  Offset rot(Offset v, double ang) =>
      Offset(v.dx * cos(ang) - v.dy * sin(ang), v.dx * sin(ang) + v.dy * cos(ang));
  final back = -dir * head;
  return [a, tip, tip + rot(back, 0.5), tip, tip + rot(back, -0.5)];
}

// ------------------------------------------------------------------ kapalı şekiller
List<Offset>? _closedShape(List<Offset> pts, Rect box, double diag) {
  var poly = _rdp(pts, diag * 0.07);
  if (poly.length > 2 && (poly.first - poly.last).distance < diag * 0.25) {
    poly = poly.sublist(0, poly.length - 1);
  }
  poly = _dropStraightVertices(poly);

  if (poly.length == 3) return [...poly, poly.first];

  if (poly.length == 4) {
    if (_axisAligned(poly)) {
      return [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft, box.topLeft];
    }
    return [...poly, poly.first];
  }

  // Daire / elips: merkezden uzaklıklar yeterince düzenli mi?
  final c = box.center;
  final rx = box.width / 2, ry = box.height / 2;
  if (rx < 8 || ry < 8) return null;
  var err = 0.0;
  for (final p in pts) {
    final nx = (p.dx - c.dx) / rx, ny = (p.dy - c.dy) / ry;
    err += (sqrt(nx * nx + ny * ny) - 1).abs();
  }
  err /= pts.length;
  if (err > 0.2) return null;

  var w = rx, h = ry;
  final ratio = rx / ry;
  if (ratio > 0.85 && ratio < 1.18) w = h = (rx + ry) / 2; // neredeyse daire → daire
  return [
    for (var i = 0; i <= 72; i++)
      Offset(c.dx + w * cos(i / 72 * 2 * pi), c.dy + h * sin(i / 72 * 2 * pi)),
  ];
}

bool _axisAligned(List<Offset> poly) {
  for (var i = 0; i < poly.length; i++) {
    final d = poly[(i + 1) % poly.length] - poly[i];
    final ang = atan2(d.dy.abs(), d.dx.abs()); // 0..90°
    final off = min(ang, pi / 2 - ang);
    if (off > 15 * pi / 180) return false;
  }
  return true;
}

/// Neredeyse düz açıdaki köşeleri kaldırır (başlangıç noktası bir kenarın
/// ortasına düşünce fazladan köşe sayılmasın).
List<Offset> _dropStraightVertices(List<Offset> poly) {
  if (poly.length < 4) return poly;
  final out = List<Offset>.of(poly);
  var changed = true;
  while (changed && out.length > 3) {
    changed = false;
    for (var i = 0; i < out.length; i++) {
      final prev = out[(i - 1 + out.length) % out.length];
      final cur = out[i];
      final next = out[(i + 1) % out.length];
      final a = cur - prev, b = next - cur;
      if (a.distance == 0 || b.distance == 0) {
        out.removeAt(i);
        changed = true;
        break;
      }
      final cosAng = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
      if (cosAng > cos(28 * pi / 180)) {
        out.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return out;
}

/// Ramer–Douglas–Peucker çizgi sadeleştirme.
List<Offset> _rdp(List<Offset> pts, double eps) {
  if (pts.length < 3) return List.of(pts);
  var maxD = 0.0;
  var idx = 0;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = sqrt(Stroke.segmentDistance2(pts[i], pts.first, pts.last));
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD <= eps) return [pts.first, pts.last];
  final left = _rdp(pts.sublist(0, idx + 1), eps);
  final right = _rdp(pts.sublist(idx), eps);
  return [...left.sublist(0, left.length - 1), ...right];
}

double _maxDeviation(List<Offset> pts, Offset a, Offset b) {
  var m = 0.0;
  for (final p in pts) {
    m = max(m, sqrt(Stroke.segmentDistance2(p, a, b)));
  }
  return m;
}

double _pathLength(List<Offset> pts) {
  var l = 0.0;
  for (var i = 1; i < pts.length; i++) {
    l += (pts[i] - pts[i - 1]).distance;
  }
  return l;
}

Rect _bounds(List<Offset> pts) {
  var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
  for (final p in pts) {
    minX = min(minX, p.dx);
    maxX = max(maxX, p.dx);
    minY = min(minY, p.dy);
    maxY = max(maxY, p.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Nokta çokgenin içinde mi? (kement seçimi için, ışın atma yöntemi)
bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
