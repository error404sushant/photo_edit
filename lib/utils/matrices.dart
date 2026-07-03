import 'dart:math' as math;

/// 4x5 color matrix helpers (row-major, 20 values) used by
/// [ColorFilter.matrix]. Adjustment values are normalized to -1..1
/// (or 0..1 for one-directional effects) and mapped to sensible ranges.
typedef ColorMatrix = List<double>;

const ColorMatrix identityMatrix = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// Applies [b] first, then [a].
ColorMatrix multiplyMatrices(ColorMatrix a, ColorMatrix b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[row * 5 + k] * b[k * 5 + col];
      }
      if (col == 4) v += a[row * 5 + 4];
      out[row * 5 + col] = v;
    }
  }
  return out;
}

ColorMatrix composeAll(Iterable<ColorMatrix> matrices) =>
    matrices.fold(identityMatrix, (acc, m) => multiplyMatrices(m, acc));

ColorMatrix brightnessMatrix(double v) {
  final o = v * 90;
  return [
    1, 0, 0, 0, o, //
    0, 1, 0, 0, o, //
    0, 0, 1, 0, o, //
    0, 0, 0, 1, 0, //
  ];
}

ColorMatrix exposureMatrix(double v) {
  final s = math.pow(2, v).toDouble();
  return [
    s, 0, 0, 0, 0, //
    0, s, 0, 0, 0, //
    0, 0, s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

ColorMatrix contrastMatrix(double v) {
  final s = 1 + v * 0.7;
  final t = (1 - s) * 128;
  return [
    s, 0, 0, 0, t, //
    0, s, 0, 0, t, //
    0, 0, s, 0, t, //
    0, 0, 0, 1, 0, //
  ];
}

ColorMatrix saturationMatrix(double v) {
  final s = (1 + v).clamp(0.0, 2.0);
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return [
    ir + s, ig, ib, 0, 0, //
    ir, ig + s, ib, 0, 0, //
    ir, ig, ib + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

ColorMatrix warmthMatrix(double v) {
  final r = 1 + v * 0.22;
  final b = 1 - v * 0.22;
  return [
    r, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, b, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Positive shifts toward magenta, negative toward green.
ColorMatrix tintMatrix(double v) {
  final g = 1 - v * 0.2;
  final rb = 1 + v * 0.06;
  return [
    rb, 0, 0, 0, 0, //
    0, g, 0, 0, 0, //
    0, 0, rb, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

ColorMatrix hueMatrix(double v) {
  final a = v * math.pi;
  final c = math.cos(a), s = math.sin(a);
  return [
    0.213 + c * 0.787 - s * 0.213,
    0.715 - c * 0.715 - s * 0.715,
    0.072 - c * 0.072 + s * 0.928,
    0,
    0, //
    0.213 - c * 0.213 + s * 0.143,
    0.715 + c * 0.285 + s * 0.140,
    0.072 - c * 0.072 - s * 0.283,
    0,
    0, //
    0.213 - c * 0.213 - s * 0.787,
    0.715 - c * 0.715 + s * 0.715,
    0.072 + c * 0.928 + s * 0.072,
    0,
    0, //
    0, 0, 0, 1, 0, //
  ];
}

/// Lifts blacks and softens contrast for a washed-out look (0..1).
ColorMatrix fadeMatrix(double v) {
  final s = 1 - v * 0.3;
  final o = v * 45;
  return [
    s, 0, 0, 0, o, //
    0, s, 0, 0, o, //
    0, 0, s, 0, o, //
    0, 0, 0, 1, 0, //
  ];
}

const ColorMatrix _sepia = [
  0.393, 0.769, 0.189, 0, 0, //
  0.349, 0.686, 0.168, 0, 0, //
  0.272, 0.534, 0.131, 0, 0, //
  0, 0, 0, 1, 0, //
];

ColorMatrix sepiaMatrix(double amount) => _lerp(identityMatrix, _sepia, amount);

ColorMatrix grayscaleMatrix(double amount) => saturationMatrix(-amount);

ColorMatrix _lerp(ColorMatrix a, ColorMatrix b, double t) =>
    List.generate(20, (i) => a[i] + (b[i] - a[i]) * t);

class FilterPreset {
  final String name;
  final ColorMatrix matrix;
  const FilterPreset(this.name, this.matrix);
}

final List<FilterPreset> filterPresets = [
  const FilterPreset('Original', identityMatrix),
  FilterPreset(
    'Vivid',
    composeAll([saturationMatrix(0.35), contrastMatrix(0.12)]),
  ),
  FilterPreset(
    'Pop',
    composeAll([
      saturationMatrix(0.55),
      contrastMatrix(0.22),
      brightnessMatrix(0.04),
    ]),
  ),
  FilterPreset(
    'Warm',
    composeAll([warmthMatrix(0.45), brightnessMatrix(0.03)]),
  ),
  FilterPreset(
    'Golden',
    composeAll([warmthMatrix(0.35), sepiaMatrix(0.25), contrastMatrix(0.08)]),
  ),
  FilterPreset(
    'Cool',
    composeAll([warmthMatrix(-0.45), brightnessMatrix(0.02)]),
  ),
  FilterPreset(
    'Arctic',
    composeAll([
      warmthMatrix(-0.35),
      saturationMatrix(-0.2),
      brightnessMatrix(0.08),
    ]),
  ),
  FilterPreset(
    'Cinema',
    composeAll([
      warmthMatrix(0.18),
      tintMatrix(-0.12),
      contrastMatrix(0.18),
      saturationMatrix(-0.08),
    ]),
  ),
  FilterPreset(
    'Retro',
    composeAll([
      sepiaMatrix(0.45),
      contrastMatrix(-0.1),
      brightnessMatrix(0.05),
    ]),
  ),
  FilterPreset('Fade', composeAll([fadeMatrix(0.6), saturationMatrix(-0.15)])),
  FilterPreset('Mono', grayscaleMatrix(1)),
  FilterPreset('Noir', composeAll([grayscaleMatrix(1), contrastMatrix(0.35)])),
  FilterPreset(
    'Silver',
    composeAll([grayscaleMatrix(1), brightnessMatrix(0.1), fadeMatrix(0.25)]),
  ),
  FilterPreset('Sepia', sepiaMatrix(0.9)),
  FilterPreset(
    'Rose',
    composeAll([
      tintMatrix(0.3),
      brightnessMatrix(0.05),
      saturationMatrix(0.1),
    ]),
  ),
  FilterPreset(
    'Forest',
    composeAll([
      tintMatrix(-0.3),
      saturationMatrix(0.15),
      contrastMatrix(0.08),
    ]),
  ),
];
