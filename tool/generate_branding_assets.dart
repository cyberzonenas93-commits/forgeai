import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final root = Directory.current.path;
  final input = File('$root/ForgeAI_iOS_Icons/icon_1024x1024.png');
  if (!input.existsSync()) {
    stderr.writeln('Missing source icon: ${input.path}');
    exitCode = 1;
    return;
  }

  final source = img.decodePng(input.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Could not decode ${input.path}');
    exitCode = 1;
    return;
  }

  var minX = source.width;
  var minY = source.height;
  var maxX = 0;
  var maxY = 0;
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      final brightness =
          (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) / 3;
      if (brightness < 90) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  const padding = 20;
  minX = (minX - padding).clamp(0, source.width - 1);
  minY = (minY - padding).clamp(0, source.height - 1);
  maxX = (maxX + padding).clamp(0, source.width - 1);
  maxY = (maxY + padding).clamp(0, source.height - 1);

  final cropSize = [maxX - minX, maxY - minY].reduce((a, b) => a > b ? a : b);
  final cropX = ((minX + maxX - cropSize) / 2).round().clamp(
    0,
    source.width - cropSize,
  );
  final cropY = ((minY + maxY - cropSize) / 2).round().clamp(
    0,
    source.height - cropSize,
  );
  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropSize,
    height: cropSize,
  );

  final visited = List.generate(
    cropped.height,
    (_) => List<bool>.filled(cropped.width, false),
  );
  final queue = <(int, int)>[];

  bool isEdgeBackground(int x, int y) {
    final pixel = cropped.getPixel(x, y);
    final r = pixel.r.toInt();
    final g = pixel.g.toInt();
    final b = pixel.b.toInt();
    final maxChannel = [r, g, b].reduce((a, b) => a > b ? a : b);
    final minChannel = [r, g, b].reduce((a, b) => a < b ? a : b);
    return minChannel > 120 &&
        maxChannel > 145 &&
        (maxChannel - minChannel) < 90;
  }

  void enqueueEdgeBackground(int x, int y) {
    if (x < 0 ||
        y < 0 ||
        x >= cropped.width ||
        y >= cropped.height ||
        visited[y][x] ||
        !isEdgeBackground(x, y)) {
      return;
    }
    visited[y][x] = true;
    queue.add((x, y));
  }

  for (var x = 0; x < cropped.width; x++) {
    enqueueEdgeBackground(x, 0);
    enqueueEdgeBackground(x, cropped.height - 1);
  }
  for (var y = 0; y < cropped.height; y++) {
    enqueueEdgeBackground(0, y);
    enqueueEdgeBackground(cropped.width - 1, y);
  }

  while (queue.isNotEmpty) {
    final (x, y) = queue.removeLast();
    cropped.setPixelRgba(x, y, 0, 0, 0, 0);
    enqueueEdgeBackground(x + 1, y);
    enqueueEdgeBackground(x - 1, y);
    enqueueEdgeBackground(x, y + 1);
    enqueueEdgeBackground(x, y - 1);
    enqueueEdgeBackground(x + 1, y + 1);
    enqueueEdgeBackground(x - 1, y - 1);
    enqueueEdgeBackground(x + 1, y - 1);
    enqueueEdgeBackground(x - 1, y + 1);
  }

  final cornerRadius = (cropSize * 0.17).round();
  for (var y = 0; y < cropped.height; y++) {
    for (var x = 0; x < cropped.width; x++) {
      if (!_insideRoundedRect(
        x,
        y,
        cropped.width,
        cropped.height,
        cornerRadius,
      )) {
        cropped.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  final canvas = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final dx = ((canvas.width - cropped.width) / 2).round();
  final dy = ((canvas.height - cropped.height) / 2).round();
  img.compositeImage(canvas, cropped, dstX: dx, dstY: dy);

  final outputDir = Directory('$root/assets/branding')
    ..createSync(recursive: true);
  final output = File('${outputDir.path}/forge_mark.png');
  output.writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generated ${output.path}');
}

bool _insideRoundedRect(int x, int y, int width, int height, int radius) {
  final left = x < radius;
  final right = x >= width - radius;
  final top = y < radius;
  final bottom = y >= height - radius;

  if ((!left && !right) || (!top && !bottom)) {
    return true;
  }

  final cx = left ? radius : width - radius - 1;
  final cy = top ? radius : height - radius - 1;
  final dx = x - cx;
  final dy = y - cy;
  return (dx * dx) + (dy * dy) <= radius * radius;
}
