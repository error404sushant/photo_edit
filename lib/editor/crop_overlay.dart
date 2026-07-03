import 'package:flutter/material.dart';

/// Interactive crop rectangle over an image area. Works in normalized
/// coordinates (0..1); the parent supplies the pixel size via LayoutBuilder.
class CropOverlay extends StatefulWidget {
  final Rect rect;
  final double? aspectRatio; // locked ratio (w/h) in *canvas* space, or null
  final ValueChanged<Rect> onChanged;

  const CropOverlay({
    super.key,
    required this.rect,
    required this.aspectRatio,
    required this.onChanged,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

enum _DragMode { none, move, tl, tr, bl, br, left, right, top, bottom }

class _CropOverlayState extends State<CropOverlay> {
  _DragMode _mode = _DragMode.none;
  static const _minSize = 0.08;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _mode = _hitTest(d.localPosition, size),
        onPanUpdate: (d) => _onDrag(d.delta, size),
        onPanEnd: (_) => _mode = _DragMode.none,
        child: CustomPaint(
          size: size,
          painter: _CropPainter(widget.rect),
        ),
      );
    });
  }

  _DragMode _hitTest(Offset pos, Size size) {
    final r = Rect.fromLTRB(
      widget.rect.left * size.width,
      widget.rect.top * size.height,
      widget.rect.right * size.width,
      widget.rect.bottom * size.height,
    );
    const grab = 24.0;
    bool near(Offset a, Offset b) => (a - b).distance < grab;
    if (near(pos, r.topLeft)) return _DragMode.tl;
    if (near(pos, r.topRight)) return _DragMode.tr;
    if (near(pos, r.bottomLeft)) return _DragMode.bl;
    if (near(pos, r.bottomRight)) return _DragMode.br;
    if ((pos.dx - r.left).abs() < grab && pos.dy > r.top && pos.dy < r.bottom) {
      return _DragMode.left;
    }
    if ((pos.dx - r.right).abs() < grab && pos.dy > r.top && pos.dy < r.bottom) {
      return _DragMode.right;
    }
    if ((pos.dy - r.top).abs() < grab && pos.dx > r.left && pos.dx < r.right) {
      return _DragMode.top;
    }
    if ((pos.dy - r.bottom).abs() < grab && pos.dx > r.left && pos.dx < r.right) {
      return _DragMode.bottom;
    }
    if (r.contains(pos)) return _DragMode.move;
    return _DragMode.none;
  }

  void _onDrag(Offset delta, Size size) {
    if (_mode == _DragMode.none) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    var r = widget.rect;

    if (_mode == _DragMode.move) {
      final nx = (r.left + dx).clamp(0.0, 1.0 - r.width);
      final ny = (r.top + dy).clamp(0.0, 1.0 - r.height);
      widget.onChanged(Rect.fromLTWH(nx, ny, r.width, r.height));
      return;
    }

    var left = r.left, top = r.top, right = r.right, bottom = r.bottom;
    switch (_mode) {
      case _DragMode.tl:
        left += dx;
        top += dy;
      case _DragMode.tr:
        right += dx;
        top += dy;
      case _DragMode.bl:
        left += dx;
        bottom += dy;
      case _DragMode.br:
        right += dx;
        bottom += dy;
      case _DragMode.left:
        left += dx;
      case _DragMode.right:
        right += dx;
      case _DragMode.top:
        top += dy;
      case _DragMode.bottom:
        bottom += dy;
      default:
        break;
    }

    left = left.clamp(0.0, right - _minSize);
    right = right.clamp(left + _minSize, 1.0);
    top = top.clamp(0.0, bottom - _minSize);
    bottom = bottom.clamp(top + _minSize, 1.0);
    var next = Rect.fromLTRB(left, top, right, bottom);

    final ratio = widget.aspectRatio;
    if (ratio != null) {
      // Enforce ratio in canvas pixel space, anchored to the dragged side.
      final canvasAspect = context.size!.width / context.size!.height;
      var w = next.width;
      var h = w * canvasAspect / ratio;
      if (h > 1) {
        h = 1;
        w = h * ratio / canvasAspect;
      }
      switch (_mode) {
        case _DragMode.tl:
        case _DragMode.left:
        case _DragMode.top:
          next = Rect.fromLTWH(next.right - w, next.bottom - h, w, h);
        case _DragMode.tr:
        case _DragMode.right:
          next = Rect.fromLTWH(next.left, next.bottom - h, w, h);
        default:
          next = Rect.fromLTWH(next.left, next.top, w, h);
      }
      next = Rect.fromLTWH(
        next.left.clamp(0.0, 1.0 - next.width),
        next.top.clamp(0.0, 1.0 - next.height),
        next.width,
        next.height,
      );
    }
    widget.onChanged(next);
  }
}

class _CropPainter extends CustomPainter {
  final Rect rect;
  _CropPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Dim everything outside the crop rect.
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(r),
      ),
      dim,
    );

    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r, border);

    // Rule-of-thirds grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }

    // Corner handles.
    final handle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    void corner(Offset c, double sx, double sy) {
      canvas.drawLine(c, c + Offset(len * sx, 0), handle);
      canvas.drawLine(c, c + Offset(0, len * sy), handle);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomLeft, 1, -1);
    corner(r.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}
