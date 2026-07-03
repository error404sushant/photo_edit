import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/editor_models.dart';
import '../utils/matrices.dart';

/// Draws [image] with orientation (quarter turns + flips) and crop so the
/// selected region exactly fills [size], using [paint] for filters.
void paintOrientedImage({
  required Canvas canvas,
  required Size size,
  required ui.Image image,
  required Rect crop,
  required int quarterTurns,
  required bool flipH,
  required bool flipV,
  required Paint paint,
}) {
  final imgW = image.width.toDouble();
  final imgH = image.height.toDouble();
  final rotated = quarterTurns.isOdd;
  final orientedW = rotated ? imgH : imgW;
  final orientedH = rotated ? imgW : imgH;

  final cropPx = Rect.fromLTWH(
    crop.left * orientedW,
    crop.top * orientedH,
    crop.width * orientedW,
    crop.height * orientedH,
  );

  canvas.save();
  canvas.clipRect(Offset.zero & size);
  // Map the cropped oriented region onto the full canvas.
  canvas.scale(size.width / cropPx.width, size.height / cropPx.height);
  canvas.translate(-cropPx.left, -cropPx.top);
  // Orient: rotate around the oriented center, then flip in image space.
  canvas.translate(orientedW / 2, orientedH / 2);
  canvas.rotate(quarterTurns * math.pi / 2);
  canvas.scale(flipH ? -1 : 1, flipV ? -1 : 1);
  canvas.translate(-imgW / 2, -imgH / 2);
  canvas.drawImage(image, Offset.zero, paint);
  canvas.restore();
}

Paint _imagePaint(ColorMatrix matrix, double blur, Size size) {
  final paint = Paint()
    ..colorFilter = ColorFilter.matrix(matrix)
    ..filterQuality = FilterQuality.medium;
  if (blur > 0) {
    // Sigma in output logical pixels so it stays consistent on export.
    final sigma = blur * size.shortestSide * 0.02;
    paint.imageFilter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.clamp,
    );
  }
  return paint;
}

/// Paints the source image with orientation (quarter turns + flips),
/// crop, color-matrix filter and optional blur applied.
class FilteredImagePainter extends CustomPainter {
  final ui.Image image;
  final ColorMatrix matrix;
  final double blur;
  final int quarterTurns;
  final bool flipH;
  final bool flipV;

  /// Crop rect normalized to the oriented image; the painted output fills
  /// [size] with exactly this region.
  final Rect crop;

  FilteredImagePainter({
    required this.image,
    required this.matrix,
    required this.blur,
    required this.quarterTurns,
    required this.flipH,
    required this.flipV,
    required this.crop,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintOrientedImage(
      canvas: canvas,
      size: size,
      image: image,
      crop: crop,
      quarterTurns: quarterTurns,
      flipH: flipH,
      flipV: flipV,
      paint: _imagePaint(matrix, blur, size),
    );
  }

  @override
  bool shouldRepaint(FilteredImagePainter old) =>
      old.image != image ||
      old.matrix != matrix ||
      old.blur != blur ||
      old.quarterTurns != quarterTurns ||
      old.flipH != flipH ||
      old.flipV != flipV ||
      old.crop != crop;
}

/// Re-paints the image inside each selective spot with the spot's own
/// adjustments, masked by a feathered radial gradient.
class SpotsPainter extends CustomPainter {
  final ui.Image image;
  final ColorMatrix globalMatrix;
  final double blur;
  final int quarterTurns;
  final bool flipH;
  final bool flipV;
  final Rect crop;
  final List<SpotEdit> spots;

  SpotsPainter({
    required this.image,
    required this.globalMatrix,
    required this.blur,
    required this.quarterTurns,
    required this.flipH,
    required this.flipV,
    required this.crop,
    required this.spots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    for (final spot in spots) {
      if (!spot.hasEffect) continue;
      final center = Offset(spot.pos.dx * size.width, spot.pos.dy * size.height);
      final radius = spot.radius * size.shortestSide;
      // Spot adjustments apply on top of the global filter chain.
      final combined = multiplyMatrices(spot.matrix, globalMatrix);
      canvas.saveLayer(bounds, Paint());
      paintOrientedImage(
        canvas: canvas,
        size: size,
        image: image,
        crop: crop,
        quarterTurns: quarterTurns,
        flipH: flipH,
        flipV: flipV,
        paint: _imagePaint(combined, blur, size),
      );
      final solid = (1 - spot.feather).clamp(0.0, 0.99);
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [Colors.white, Colors.white, Colors.white.withValues(alpha: 0)],
            [0, solid, 1],
          ),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SpotsPainter old) => true;
}

/// Dashed outlines showing where the selective spots are while editing.
class SpotOutlinePainter extends CustomPainter {
  final List<SpotEdit> spots;
  final int? selected;
  SpotOutlinePainter(this.spots, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < spots.length; i++) {
      final spot = spots[i];
      final center =
          Offset(spot.pos.dx * size.width, spot.pos.dy * size.height);
      final radius = spot.radius * size.shortestSide;
      final color = i == selected ? Colors.lightBlueAccent : Colors.white70;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == selected ? 2 : 1.2;
      // Dashed circle.
      const dashes = 32;
      for (var d = 0; d < dashes; d += 2) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          d * 2 * math.pi / dashes,
          2 * math.pi / dashes,
          false,
          paint,
        );
      }
      canvas.drawCircle(center, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(SpotOutlinePainter old) => true;
}

class VignettePainter extends CustomPainter {
  final double strength;
  VignettePainter(this.strength);

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        size.longestSide * 0.75,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: strength * 0.85),
        ],
        [1 - strength * 0.55, 1.0],
      );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(VignettePainter old) => old.strength != strength;
}

class StrokesPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? active;
  StrokesPainter(this.strokes, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final stroke in [...strokes, ?active]) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawPoints(
          ui.PointMode.points,
          [Offset(stroke.points[0].dx * size.width, stroke.points[0].dy * size.height)],
          paint..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points[0].dx * size.width, stroke.points[0].dy * size.height);
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(StrokesPainter old) => true;
}
