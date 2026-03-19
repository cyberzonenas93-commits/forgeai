import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  final root = Directory.current.path;
  final sourceFile = File('$root/ForgeAI_iOS_Icons/icon_1024x1024.png');
  if (!sourceFile.existsSync()) {
    stderr.writeln('Missing source icon: ${sourceFile.path}');
    exitCode = 1;
    return;
  }
  final output = File('$root/assets/branding/forge_mark.png');

  final source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode ${sourceFile.path}');
    exitCode = 1;
    return;
  }

  final edgeBackground = List.generate(
    source.height,
    (_) => List<bool>.filled(source.width, false),
  );
  final queue = <(int, int)>[];

  bool isEdgeBackground(int x, int y) {
    final pixel = source.getPixel(x, y);
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    final brightness = (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    return brightness > 232 && (maxChannel - minChannel) < 16;
  }

  void enqueueEdgeBackground(int x, int y) {
    if (x < 0 ||
        y < 0 ||
        x >= source.width ||
        y >= source.height ||
        edgeBackground[y][x] ||
        !isEdgeBackground(x, y)) {
      return;
    }
    edgeBackground[y][x] = true;
    queue.add((x, y));
  }

  for (var x = 0; x < source.width; x++) {
    enqueueEdgeBackground(x, 0);
    enqueueEdgeBackground(x, source.height - 1);
  }
  for (var y = 0; y < source.height; y++) {
    enqueueEdgeBackground(0, y);
    enqueueEdgeBackground(source.width - 1, y);
  }

  while (queue.isNotEmpty) {
    final (x, y) = queue.removeLast();
    enqueueEdgeBackground(x + 1, y);
    enqueueEdgeBackground(x - 1, y);
    enqueueEdgeBackground(x, y + 1);
    enqueueEdgeBackground(x, y - 1);
  }

  final connectedGlyph = List.generate(
    source.height,
    (_) => List<bool>.filled(source.width, false),
  );
  final glyphQueue = <(int, int)>[];

  double brightnessAt(int x, int y) {
    final pixel = source.getPixel(x, y);
    return (0.2126 * pixel.r) + (0.7152 * pixel.g) + (0.0722 * pixel.b);
  }

  double blueGlowAt(int x, int y) {
    final pixel = source.getPixel(x, y);
    return math.max(0.0, pixel.b - ((pixel.r + pixel.g) / 2));
  }

  bool isGlyphSeed(int x, int y) {
    final brightness = brightnessAt(x, y);
    final blueGlow = blueGlowAt(x, y);
    return brightness > 208 || (brightness > 155 && blueGlow > 18);
  }

  bool isGlyphNeighbor(int x, int y) {
    final brightness = brightnessAt(x, y);
    final blueGlow = blueGlowAt(x, y);
    return brightness > 108 || (brightness > 86 && blueGlow > 14);
  }

  void enqueueGlyph(int x, int y) {
    if (x < 0 ||
        y < 0 ||
        x >= source.width ||
        y >= source.height ||
        edgeBackground[y][x] ||
        connectedGlyph[y][x] ||
        !isGlyphNeighbor(x, y)) {
      return;
    }
    connectedGlyph[y][x] = true;
    glyphQueue.add((x, y));
  }

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (edgeBackground[y][x] || !isGlyphSeed(x, y)) {
        continue;
      }
      connectedGlyph[y][x] = true;
      glyphQueue.add((x, y));
    }
  }

  while (glyphQueue.isNotEmpty) {
    final (x, y) = glyphQueue.removeLast();
    enqueueGlyph(x + 1, y);
    enqueueGlyph(x - 1, y);
    enqueueGlyph(x, y + 1);
    enqueueGlyph(x, y - 1);
    enqueueGlyph(x + 1, y + 1);
    enqueueGlyph(x + 1, y - 1);
    enqueueGlyph(x - 1, y + 1);
    enqueueGlyph(x - 1, y - 1);
  }

  final extracted = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  img.fill(extracted, color: img.ColorRgba8(0, 0, 0, 0));

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      if (!connectedGlyph[y][x]) {
        continue;
      }
      final pixel = source.getPixel(x, y);
      final originalAlpha = pixel.a.toInt();
      if (originalAlpha == 0) {
        continue;
      }

      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();
      final brightness = (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
      final blueGlow = math.max(0.0, b - ((r + g) / 2));
      final highlightScore = _clamp01((brightness - 140) / 72);
      final glowScore =
          _clamp01((brightness - 96) / 70) * _clamp01((blueGlow - 12) / 18);
      final keepScore = math.max(highlightScore, glowScore);
      if (keepScore <= 0) {
        continue;
      }

      final easedScore = math.pow(keepScore, 0.82).toDouble();
      final alpha = (originalAlpha * easedScore).round().clamp(0, 255);
      extracted.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
    }
  }

  final alphaBounds = _alphaBounds(extracted);
  if (alphaBounds == null) {
    stderr.writeln('No visible mark pixels were extracted.');
    exitCode = 1;
    return;
  }

  final cropped = img.copyCrop(
    extracted,
    x: alphaBounds.$1,
    y: alphaBounds.$2,
    width: alphaBounds.$3,
    height: alphaBounds.$4,
  );

  const targetSize = 1024;
  const targetInset = 150;
  final targetInnerSize = targetSize - (targetInset * 2);
  final scale = math.min(
    targetInnerSize / cropped.width,
    targetInnerSize / cropped.height,
  );
  final resized = img.copyResize(
    cropped,
    width: math.max(1, (cropped.width * scale).round()),
    height: math.max(1, (cropped.height * scale).round()),
    interpolation: img.Interpolation.cubic,
  );

  final canvas = img.Image(width: targetSize, height: targetSize, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final dx = ((targetSize - resized.width) / 2).round();
  final dy = ((targetSize - resized.height) / 2).round();
  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  _retainCenterConnectedPixels(canvas);

  output.writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Updated ${output.path}');
}

double _clamp01(double value) => value.clamp(0.0, 1.0);

(int, int, int, int)? _alphaBounds(img.Image image) {
  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (image.getPixel(x, y).a.toInt() == 0) {
        continue;
      }
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  if (maxX < minX || maxY < minY) {
    return null;
  }

  return (minX, minY, maxX - minX + 1, maxY - minY + 1);
}

void _retainCenterConnectedPixels(img.Image image) {
  final keep = List.generate(
    image.height,
    (_) => List<bool>.filled(image.width, false),
  );
  final queue = <(int, int)>[];
  final startX = image.width ~/ 4;
  final endX = (image.width * 3) ~/ 4;
  final startY = image.height ~/ 4;
  final endY = (image.height * 3) ~/ 4;

  for (var y = startY; y < endY; y++) {
    for (var x = startX; x < endX; x++) {
      if (image.getPixel(x, y).a.toInt() == 0 || keep[y][x]) {
        continue;
      }
      keep[y][x] = true;
      queue.add((x, y));
    }
  }

  while (queue.isNotEmpty) {
    final (x, y) = queue.removeLast();
    for (final (nx, ny) in [
      (x + 1, y),
      (x - 1, y),
      (x, y + 1),
      (x, y - 1),
      (x + 1, y + 1),
      (x + 1, y - 1),
      (x - 1, y + 1),
      (x - 1, y - 1),
    ]) {
      if (nx < 0 ||
          ny < 0 ||
          nx >= image.width ||
          ny >= image.height ||
          keep[ny][nx] ||
          image.getPixel(nx, ny).a.toInt() == 0) {
        continue;
      }
      keep[ny][nx] = true;
      queue.add((nx, ny));
    }
  }

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (!keep[y][x]) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
}
