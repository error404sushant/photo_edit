import 'package:flutter/material.dart';

import '../utils/matrices.dart';

enum AdjustType {
  brightness('Brightness', Icons.brightness_6_outlined),
  exposure('Exposure', Icons.exposure),
  contrast('Contrast', Icons.contrast),
  saturation('Saturation', Icons.water_drop_outlined),
  warmth('Warmth', Icons.thermostat_outlined),
  tint('Tint', Icons.colorize_outlined),
  hue('Hue', Icons.palette_outlined),
  fade('Fade', Icons.blur_linear),
  vignette('Vignette', Icons.vignette_outlined),
  blur('Blur', Icons.blur_on);

  final String label;
  final IconData icon;
  const AdjustType(this.label, this.icon);

  /// One-directional effects use a 0..1 slider; the rest are -1..1.
  bool get isOneSided =>
      this == AdjustType.fade ||
      this == AdjustType.vignette ||
      this == AdjustType.blur;
}

class Stroke {
  /// Points normalized to 0..1 of the canvas.
  final List<Offset> points;
  final Color color;

  /// Width as a fraction of canvas width.
  final double width;

  Stroke({required this.points, required this.color, required this.width});

  Stroke copy() => Stroke(points: List.of(points), color: color, width: width);
}

/// Adjustments available inside a selective spot.
const List<AdjustType> kSpotAdjustTypes = [
  AdjustType.brightness,
  AdjustType.exposure,
  AdjustType.contrast,
  AdjustType.saturation,
  AdjustType.warmth,
];

/// A feathered circular region with its own local adjustments
/// (e.g. brighten just a face).
class SpotEdit {
  Offset pos; // normalized center 0..1
  double radius; // fraction of the canvas shortest side
  double feather; // 0 = hard edge, 1 = fully soft
  Map<AdjustType, double> adjustments;

  SpotEdit({
    this.pos = const Offset(0.5, 0.5),
    this.radius = 0.22,
    this.feather = 0.6,
    Map<AdjustType, double>? adjustments,
  }) : adjustments =
            adjustments ?? {for (final t in kSpotAdjustTypes) t: 0.0};

  SpotEdit copy() => SpotEdit(
        pos: pos,
        radius: radius,
        feather: feather,
        adjustments: Map.of(adjustments),
      );

  bool get hasEffect => adjustments.values.any((v) => v.abs() > 0.001);

  ColorMatrix get matrix => composeAll([
        brightnessMatrix(adjustments[AdjustType.brightness]!),
        exposureMatrix(adjustments[AdjustType.exposure]!),
        contrastMatrix(adjustments[AdjustType.contrast]!),
        saturationMatrix(adjustments[AdjustType.saturation]!),
        warmthMatrix(adjustments[AdjustType.warmth]!),
      ]);
}

enum OverlayKind { text, sticker }

class OverlayItem {
  OverlayKind kind;
  String text;
  Offset pos; // normalized center 0..1
  double scale;
  double rotation;
  Color color;
  String fontFamily;
  bool hasBackground;

  OverlayItem({
    required this.kind,
    required this.text,
    this.pos = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
    this.color = Colors.white,
    this.fontFamily = 'Roboto',
    this.hasBackground = false,
  });

  OverlayItem copy() => OverlayItem(
        kind: kind,
        text: text,
        pos: pos,
        scale: scale,
        rotation: rotation,
        color: color,
        fontFamily: fontFamily,
        hasBackground: hasBackground,
      );
}

/// Full editing state; snapshots of this power undo/redo.
class EditSnapshot {
  final Map<AdjustType, double> adjustments;
  final int filterIndex;
  final double filterStrength;
  final int quarterTurns;
  final bool flipH;
  final bool flipV;

  /// Crop rect normalized to the *oriented* (rotated/flipped) image.
  final Rect crop;
  final List<Stroke> strokes;
  final List<OverlayItem> items;
  final List<SpotEdit> spots;

  EditSnapshot({
    required this.adjustments,
    required this.filterIndex,
    required this.filterStrength,
    required this.quarterTurns,
    required this.flipH,
    required this.flipV,
    required this.crop,
    required this.strokes,
    required this.items,
    required this.spots,
  });

  factory EditSnapshot.initial() => EditSnapshot(
        adjustments: {for (final t in AdjustType.values) t: 0.0},
        filterIndex: 0,
        filterStrength: 1,
        quarterTurns: 0,
        flipH: false,
        flipV: false,
        crop: const Rect.fromLTWH(0, 0, 1, 1),
        strokes: [],
        items: [],
        spots: [],
      );

  EditSnapshot copyWith({
    int? filterIndex,
    double? filterStrength,
    int? quarterTurns,
    bool? flipH,
    bool? flipV,
    Rect? crop,
  }) =>
      EditSnapshot(
        adjustments: adjustments,
        filterIndex: filterIndex ?? this.filterIndex,
        filterStrength: filterStrength ?? this.filterStrength,
        quarterTurns: quarterTurns ?? this.quarterTurns,
        flipH: flipH ?? this.flipH,
        flipV: flipV ?? this.flipV,
        crop: crop ?? this.crop,
        strokes: strokes,
        items: items,
        spots: spots,
      );

  EditSnapshot copy() => EditSnapshot(
        adjustments: Map.of(adjustments),
        filterIndex: filterIndex,
        filterStrength: filterStrength,
        quarterTurns: quarterTurns,
        flipH: flipH,
        flipV: flipV,
        crop: crop,
        strokes: strokes.map((s) => s.copy()).toList(),
        items: items.map((i) => i.copy()).toList(),
        spots: spots.map((s) => s.copy()).toList(),
      );

  /// The combined color matrix of the preset filter plus manual adjustments.
  ColorMatrix get colorMatrix {
    final preset = filterPresets[filterIndex].matrix;
    final blended = List.generate(
      20,
      (i) => identityMatrix[i] + (preset[i] - identityMatrix[i]) * filterStrength,
    );
    return composeAll([
      blended,
      brightnessMatrix(adjustments[AdjustType.brightness]!),
      exposureMatrix(adjustments[AdjustType.exposure]!),
      contrastMatrix(adjustments[AdjustType.contrast]!),
      saturationMatrix(adjustments[AdjustType.saturation]!),
      warmthMatrix(adjustments[AdjustType.warmth]!),
      tintMatrix(adjustments[AdjustType.tint]!),
      hueMatrix(adjustments[AdjustType.hue]!),
      fadeMatrix(adjustments[AdjustType.fade]!),
    ]);
  }
}
