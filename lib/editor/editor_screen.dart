import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/editor_models.dart';
import '../utils/matrices.dart';
import '../utils/saver.dart';
import 'crop_overlay.dart';
import 'painters.dart';

enum Tool {
  filters('Filters', Icons.auto_awesome),
  adjust('Adjust', Icons.tune),
  selective('Selective', Icons.center_focus_strong),
  crop('Crop', Icons.crop_rotate),
  draw('Draw', Icons.brush_outlined),
  text('Text', Icons.text_fields),
  stickers('Stickers', Icons.emoji_emotions_outlined);

  final String label;
  final IconData icon;
  const Tool(this.label, this.icon);
}

const List<String> kTextFonts = [
  'Roboto',
  'Oswald',
  'Lobster',
  'Pacifico',
  'Caveat',
  'Bebas Neue',
  'Playfair Display',
];

const List<Color> kPalette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF5252),
  Color(0xFFFF9800),
  Color(0xFFFFEB3B),
  Color(0xFF4CAF50),
  Color(0xFF00BCD4),
  Color(0xFF2196F3),
  Color(0xFF9C27B0),
  Color(0xFFE91E63),
];

const List<String> kStickers = [
  '😀', '😂', '😍', '😎', '🥳', '😜', '🤩', '😇', '🥰', '😴',
  '❤️', '🔥', '⭐', '✨', '💯', '🎉', '🎈', '🌈', '⚡', '💥',
  '👍', '👏', '✌️', '🤘', '💪', '🙌', '🐶', '🐱', '🦄', '🌸',
  '🍕', '🍩', '☕', '🏆', '🎵', '📸', '🚀', '🌙', '☀️', '🌊',
];

class EditorScreen extends StatefulWidget {
  final ui.Image image;
  const EditorScreen({super.key, required this.image});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  EditSnapshot edit = EditSnapshot.initial();
  final List<EditSnapshot> _undoStack = [];
  final List<EditSnapshot> _redoStack = [];

  Tool _tool = Tool.filters;
  AdjustType _adjust = AdjustType.brightness;
  int? _selectedItem;
  bool _comparing = false;
  bool _saving = false;

  // Draw tool state.
  Color _brushColor = const Color(0xFFFF5252);
  double _brushWidth = 0.015;
  Stroke? _activeStroke;

  // Crop tool state.
  late Rect _cropDraft;
  double? _cropAspect;

  // Selective tool state.
  int? _selectedSpot;
  AdjustType _spotAdjust = AdjustType.brightness;
  double _spotBaseRadius = 0.22;
  bool _enhancing = false;

  // Overlay gesture state.
  double _gestureBaseScale = 1;
  double _gestureBaseRotation = 0;

  final GlobalKey _canvasKey = GlobalKey();

  double get _orientedWidth => edit.quarterTurns.isOdd
      ? widget.image.height.toDouble()
      : widget.image.width.toDouble();
  double get _orientedHeight => edit.quarterTurns.isOdd
      ? widget.image.width.toDouble()
      : widget.image.height.toDouble();

  double get _canvasAspect {
    if (_tool == Tool.crop) return _orientedWidth / _orientedHeight;
    return (edit.crop.width * _orientedWidth) /
        (edit.crop.height * _orientedHeight);
  }

  // ---------------------------------------------------------------- history

  void _push() {
    _undoStack.add(edit.copy());
    _redoStack.clear();
    if (_undoStack.length > 60) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(edit.copy());
      edit = _undoStack.removeLast();
      _selectedItem = null;
      _cropDraft = edit.crop;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(edit.copy());
      edit = _redoStack.removeLast();
      _selectedItem = null;
      _cropDraft = edit.crop;
    });
  }

  void _resetAll() {
    _push();
    setState(() {
      edit = EditSnapshot.initial();
      _selectedItem = null;
      _cropDraft = edit.crop;
    });
  }

  @override
  void initState() {
    super.initState();
    _cropDraft = edit.crop;
  }

  // ------------------------------------------------------------------ save

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _selectedItem = null;
    });
    try {
      // Let the frame without selection chrome paint first.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _canvasKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final logicalWidth = boundary.size.width;
      final targetWidth = edit.crop.width * _orientedWidth;
      final ratio = (targetWidth / logicalWidth).clamp(1.0, 8.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final name = 'photo_edit_${DateTime.now().millisecondsSinceEpoch}.png';
      await saveImageBytes(data!.buffer.asUint8List(), name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image exported — check your downloads')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101014),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: AspectRatio(
                  aspectRatio: _canvasAspect,
                  child: _tool == Tool.crop ? _buildCropCanvas() : _buildCanvas(),
                ),
              ),
            ),
          ),
          _buildPanel(),
          _buildToolBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF16161C),
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close',
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text('Photo Editor', style: TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          icon: _enhancing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high, color: Colors.amberAccent),
          tooltip: 'AI Enhance — auto-fix light & color',
          onPressed: _enhancing ? null : _aiEnhance,
        ),
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Undo',
          onPressed: _undoStack.isEmpty ? null : _undo,
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          tooltip: 'Redo',
          onPressed: _redoStack.isEmpty ? null : _redo,
        ),
        GestureDetector(
          onTapDown: (_) => setState(() => _comparing = true),
          onTapUp: (_) => setState(() => _comparing = false),
          onTapCancel: () => setState(() => _comparing = false),
          child: IconButton(
            icon: Icon(_comparing ? Icons.visibility : Icons.visibility_outlined),
            tooltip: 'Hold to compare with original',
            onPressed: () {},
          ),
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: 'Reset all edits',
          onPressed: _resetAll,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, size: 18),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- canvas

  Widget _buildCanvas() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final showEdits = !_comparing;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: RepaintBoundary(
          key: _canvasKey,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedItem = null),
                child: CustomPaint(
                  painter: FilteredImagePainter(
                    image: widget.image,
                    matrix: showEdits ? edit.colorMatrix : identityMatrix,
                    blur: showEdits ? edit.adjustments[AdjustType.blur]! : 0,
                    quarterTurns: edit.quarterTurns,
                    flipH: edit.flipH,
                    flipV: edit.flipV,
                    crop: edit.crop,
                  ),
                ),
              ),
              if (showEdits) ...[
                IgnorePointer(
                  child: CustomPaint(
                    painter: SpotsPainter(
                      image: widget.image,
                      globalMatrix: edit.colorMatrix,
                      blur: edit.adjustments[AdjustType.blur]!,
                      quarterTurns: edit.quarterTurns,
                      flipH: edit.flipH,
                      flipV: edit.flipV,
                      crop: edit.crop,
                      spots: edit.spots,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter:
                        VignettePainter(edit.adjustments[AdjustType.vignette]!),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: StrokesPainter(edit.strokes, _activeStroke),
                  ),
                ),
                for (var i = 0; i < edit.items.length; i++)
                  _buildOverlayItem(i, size),
                if (_tool == Tool.draw) _buildDrawLayer(size),
                if (_tool == Tool.selective && !_saving) ...[
                  IgnorePointer(
                    child: CustomPaint(
                      painter: SpotOutlinePainter(edit.spots, _selectedSpot),
                    ),
                  ),
                  _buildSpotGestureLayer(size),
                ],
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildDrawLayer(Size size) {
    Offset norm(Offset p) => Offset(
          (p.dx / size.width).clamp(0.0, 1.0),
          (p.dy / size.height).clamp(0.0, 1.0),
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _activeStroke = Stroke(
          points: [norm(d.localPosition)],
          color: _brushColor,
          width: _brushWidth,
        );
      }),
      onPanUpdate: (d) => setState(() {
        _activeStroke?.points.add(norm(d.localPosition));
      }),
      onPanEnd: (_) {
        if (_activeStroke == null) return;
        _push();
        setState(() {
          edit.strokes.add(_activeStroke!);
          _activeStroke = null;
        });
      },
    );
  }

  /// Tap to select a spot; drag to move it; pinch to resize.
  Widget _buildSpotGestureLayer(Size size) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final p = d.localPosition;
        for (var i = edit.spots.length - 1; i >= 0; i--) {
          final spot = edit.spots[i];
          final center =
              Offset(spot.pos.dx * size.width, spot.pos.dy * size.height);
          if ((p - center).distance <= spot.radius * size.shortestSide) {
            setState(() => _selectedSpot = i);
            return;
          }
        }
        setState(() => _selectedSpot = null);
      },
      onScaleStart: (_) {
        if (_selectedSpot == null) return;
        _push();
        _spotBaseRadius = edit.spots[_selectedSpot!].radius;
      },
      onScaleUpdate: (d) {
        if (_selectedSpot == null) return;
        setState(() {
          final spot = edit.spots[_selectedSpot!];
          spot.pos += Offset(
            d.focalPointDelta.dx / size.width,
            d.focalPointDelta.dy / size.height,
          );
          spot.pos = Offset(
            spot.pos.dx.clamp(0.0, 1.0),
            spot.pos.dy.clamp(0.0, 1.0),
          );
          spot.radius = (_spotBaseRadius * d.scale).clamp(0.05, 0.8);
        });
      },
    );
  }

  Widget _buildOverlayItem(int index, Size canvasSize) {
    final item = edit.items[index];
    final selected = index == _selectedItem;
    final base = item.kind == OverlayKind.sticker ? 0.16 : 0.075;
    final fontSize = canvasSize.width * base * item.scale;

    Widget content;
    if (item.kind == OverlayKind.sticker) {
      content = Text(item.text, style: TextStyle(fontSize: fontSize));
    } else {
      content = Container(
        padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.3,
          vertical: fontSize * 0.12,
        ),
        decoration: item.hasBackground
            ? BoxDecoration(
                color: item.color.computeLuminance() > 0.5
                    ? Colors.black.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(fontSize * 0.2),
              )
            : null,
        child: Text(
          item.text,
          textAlign: TextAlign.center,
          style: GoogleFonts.getFont(
            item.fontFamily,
            fontSize: fontSize,
            color: item.color,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
      );
    }

    content = Container(
      decoration: BoxDecoration(
        border: selected
            ? Border.all(color: Colors.lightBlueAccent, width: 1.5)
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: content,
    );

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: _tool == Tool.draw,
        child: Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(
              (item.pos.dx - 0.5) * canvasSize.width,
              (item.pos.dy - 0.5) * canvasSize.height,
            ),
            child: Transform.rotate(
              angle: item.rotation,
              child: GestureDetector(
                onTap: () => setState(() {
                  _selectedItem = index;
                  _tool = item.kind == OverlayKind.sticker
                      ? Tool.stickers
                      : Tool.text;
                }),
                onDoubleTap: item.kind == OverlayKind.text
                    ? () => _editTextItem(index)
                    : null,
                onScaleStart: (_) {
                  _push();
                  _gestureBaseScale = item.scale;
                  _gestureBaseRotation = item.rotation;
                  setState(() => _selectedItem = index);
                },
                onScaleUpdate: (d) => setState(() {
                  item.pos += Offset(
                    d.focalPointDelta.dx / canvasSize.width,
                    d.focalPointDelta.dy / canvasSize.height,
                  );
                  item.pos = Offset(
                    item.pos.dx.clamp(0.0, 1.0),
                    item.pos.dy.clamp(0.0, 1.0),
                  );
                  item.scale =
                      (_gestureBaseScale * d.scale).clamp(0.2, 6.0);
                  item.rotation = _gestureBaseRotation + d.rotation;
                }),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropCanvas() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: FilteredImagePainter(
              image: widget.image,
              matrix: edit.colorMatrix,
              blur: 0,
              quarterTurns: edit.quarterTurns,
              flipH: edit.flipH,
              flipV: edit.flipV,
              crop: const Rect.fromLTWH(0, 0, 1, 1),
            ),
          ),
          CropOverlay(
            rect: _cropDraft,
            aspectRatio: _cropAspect,
            onChanged: (r) => setState(() => _cropDraft = r),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- panels

  Widget _buildToolBar() {
    return Container(
      color: const Color(0xFF16161C),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final tool in Tool.values)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() {
                    _tool = tool;
                    if (tool == Tool.crop) _cropDraft = edit.crop;
                    if (tool != Tool.text && tool != Tool.stickers) {
                      _selectedItem = null;
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tool.icon,
                          size: 22,
                          color: _tool == tool
                              ? Colors.lightBlueAccent
                              : Colors.white60,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tool.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: _tool == tool
                                ? Colors.lightBlueAccent
                                : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final Widget child = switch (_tool) {
      Tool.filters => _filterPanel(),
      Tool.adjust => _adjustPanel(),
      Tool.selective => _selectivePanel(),
      Tool.crop => _cropPanel(),
      Tool.draw => _drawPanel(),
      Tool.text => _textPanel(),
      Tool.stickers => _stickerPanel(),
    };
    return Container(
      color: const Color(0xFF1C1C24),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: child,
    );
  }

  // Filters -----------------------------------------------------------------

  Widget _filterPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: filterPresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final preset = filterPresets[i];
              final selected = edit.filterIndex == i;
              return GestureDetector(
                onTap: () {
                  _push();
                  setState(() => edit = edit.copyWith(filterIndex: i));
                },
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? Colors.lightBlueAccent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(
                        painter: FilteredImagePainter(
                          image: widget.image,
                          matrix: preset.matrix,
                          blur: 0,
                          quarterTurns: 0,
                          flipH: false,
                          flipV: false,
                          crop: _thumbCrop(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.lightBlueAccent : Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (edit.filterIndex != 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Strength',
                    style: TextStyle(fontSize: 12, color: Colors.white70)),
                Expanded(
                  child: Slider(
                    value: edit.filterStrength,
                    onChangeStart: (_) => _push(),
                    onChanged: (v) => setState(
                        () => edit = edit.copyWith(filterStrength: v)),
                  ),
                ),
                Text('${(edit.filterStrength * 100).round()}%',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
      ],
    );
  }

  /// Square center crop for filter thumbnails.
  Rect _thumbCrop() {
    final w = widget.image.width.toDouble();
    final h = widget.image.height.toDouble();
    if (w > h) {
      final f = h / w;
      return Rect.fromLTWH((1 - f) / 2, 0, f, 1);
    }
    final f = w / h;
    return Rect.fromLTWH(0, (1 - f) / 2, 1, f);
  }

  // Adjust ------------------------------------------------------------------

  Widget _adjustPanel() {
    final value = edit.adjustments[_adjust]!;
    final oneSided = _adjust.isOneSided;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: AdjustType.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final type = AdjustType.values[i];
              final selected = type == _adjust;
              final touched = edit.adjustments[type]!.abs() > 0.001;
              return GestureDetector(
                onTap: () => setState(() => _adjust = type),
                child: Container(
                  width: 76,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.lightBlueAccent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(type.icon,
                          size: 22,
                          color: selected
                              ? Colors.lightBlueAccent
                              : Colors.white70),
                      const SizedBox(height: 4),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: selected
                              ? Colors.lightBlueAccent
                              : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: touched
                              ? Colors.amberAccent
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  oneSided
                      ? '${(value * 100).round()}'
                      : '${value >= 0 ? '+' : ''}${(value * 100).round()}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: oneSided ? 0 : -1,
                  max: 1,
                  onChangeStart: (_) => _push(),
                  onChanged: (v) =>
                      setState(() => edit.adjustments[_adjust] = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Reset ${_adjust.label}',
                onPressed: value.abs() < 0.001
                    ? null
                    : () {
                        _push();
                        setState(() => edit.adjustments[_adjust] = 0);
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Selective ---------------------------------------------------------------

  Widget _selectivePanel() {
    final spot = _selectedSpot != null && _selectedSpot! < edit.spots.length
        ? edit.spots[_selectedSpot!]
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  _push();
                  setState(() {
                    edit.spots.add(SpotEdit());
                    _selectedSpot = edit.spots.length - 1;
                  });
                },
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add spot'),
              ),
              const SizedBox(width: 10),
              for (var i = 0; i < edit.spots.length; i++) ...[
                ChoiceChip(
                  label: Text('Spot ${i + 1}'),
                  selected: _selectedSpot == i,
                  onSelected: (_) => setState(() => _selectedSpot = i),
                ),
                const SizedBox(width: 8),
              ],
              if (spot != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete spot',
                  onPressed: () {
                    _push();
                    setState(() {
                      edit.spots.removeAt(_selectedSpot!);
                      _selectedSpot = null;
                    });
                  },
                ),
            ],
          ),
        ),
        if (spot == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Add a spot, drag it over the area to fix (e.g. a dark face), then adjust below',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('Size',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
                Expanded(
                  child: Slider(
                    value: spot.radius,
                    min: 0.05,
                    max: 0.8,
                    onChangeStart: (_) => _push(),
                    onChanged: (v) => setState(() => spot.radius = v),
                  ),
                ),
                const Text('Feather',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
                Expanded(
                  child: Slider(
                    value: spot.feather,
                    onChangeStart: (_) => _push(),
                    onChanged: (v) => setState(() => spot.feather = v),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kSpotAdjustTypes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final type = kSpotAdjustTypes[i];
                final touched = spot.adjustments[type]!.abs() > 0.001;
                return ChoiceChip(
                  avatar: Icon(type.icon, size: 16),
                  label: Text(type.label + (touched ? ' •' : '')),
                  selected: _spotAdjust == type,
                  onSelected: (_) => setState(() => _spotAdjust = type),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${spot.adjustments[_spotAdjust]! >= 0 ? '+' : ''}'
                    '${(spot.adjustments[_spotAdjust]! * 100).round()}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: spot.adjustments[_spotAdjust]!,
                    min: -1,
                    max: 1,
                    onChangeStart: (_) => _push(),
                    onChanged: (v) =>
                        setState(() => spot.adjustments[_spotAdjust] = v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Reset ${_spotAdjust.label}',
                  onPressed: spot.adjustments[_spotAdjust]!.abs() < 0.001
                      ? null
                      : () {
                          _push();
                          setState(() => spot.adjustments[_spotAdjust] = 0);
                        },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // AI enhance ----------------------------------------------------------------

  /// Samples the image at low resolution and derives auto corrections from
  /// its luminance / contrast / saturation / color-cast statistics.
  Future<void> _aiEnhance() async {
    setState(() => _enhancing = true);
    try {
      const sample = 64;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        widget.image,
        Rect.fromLTWH(0, 0, widget.image.width.toDouble(),
            widget.image.height.toDouble()),
        const Rect.fromLTWH(0, 0, sample * 1.0, sample * 1.0),
        Paint()..filterQuality = FilterQuality.low,
      );
      final small = await recorder.endRecording().toImage(sample, sample);
      final data =
          await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      final px = data!.buffer.asUint8List();

      var sumSat = 0.0, sumR = 0.0, sumB = 0.0;
      final lums = <double>[];
      final count = px.length ~/ 4;
      for (var i = 0; i < px.length; i += 4) {
        final r = px[i] / 255.0, g = px[i + 1] / 255.0, b = px[i + 2] / 255.0;
        lums.add(0.2126 * r + 0.7152 * g + 0.0722 * b);
        final hi = math.max(r, math.max(g, b));
        final lo = math.min(r, math.min(g, b));
        sumSat += hi == 0 ? 0 : (hi - lo) / hi;
        sumR += r;
        sumB += b;
      }
      final meanSat = sumSat / count;
      lums.sort();
      double pct(double p) => lums[(p * (lums.length - 1)).round()];
      final median = pct(0.5);
      final shadows = pct(0.05);
      final spread = pct(0.95) - shadows;

      // Exposure: brighten dim photos toward balanced mid-tones; only pull
      // down clearly overexposed ones; otherwise add a small lift so the
      // enhancement is visible.
      double exposure;
      if (median < 0.45) {
        exposure =
            (math.log(0.52 / math.max(median, 0.08)) / math.ln2).clamp(0.0, 0.5);
      } else if (median > 0.65) {
        exposure = (math.log(0.58 / median) / math.ln2).clamp(-0.3, 0.0);
      } else {
        exposure = 0.06;
      }

      // Lift crushed shadows a touch.
      final brightness = shadows < 0.06 ? 0.08 : 0.0;

      // Contrast: expand flat histograms; keep a minimum punch unless the
      // image already spans the full tonal range.
      var contrast = ((0.8 - spread) * 0.8).clamp(0.0, 0.3);
      if (spread < 0.9) contrast = math.max(contrast, 0.12);

      // Saturation: pull dull colors toward lively, minimum pop unless the
      // image is already very colorful.
      var saturation = ((0.38 - meanSat) * 1.5).clamp(0.0, 0.35);
      if (meanSat < 0.5) saturation = math.max(saturation, 0.15);

      // Counter a blue/orange cast; if neutral, add a hint of warmth.
      var warmth = (sumB - sumR) / count * 0.9;
      if (warmth.abs() < 0.03) warmth = 0.05;
      warmth = warmth.clamp(-0.15, 0.18);

      _push();
      setState(() {
        edit.adjustments[AdjustType.exposure] = exposure;
        edit.adjustments[AdjustType.brightness] = brightness;
        edit.adjustments[AdjustType.contrast] = contrast;
        edit.adjustments[AdjustType.saturation] = saturation;
        edit.adjustments[AdjustType.warmth] = warmth;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'AI Enhance applied ✨ — hold the eye icon to compare, tweak in Adjust, or undo'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enhancing = false);
    }
  }

  // Crop --------------------------------------------------------------------

  static const _aspectOptions = <(String, double?)>[
    ('Free', null),
    ('1:1', 1),
    ('4:3', 4 / 3),
    ('3:4', 3 / 4),
    ('16:9', 16 / 9),
    ('9:16', 9 / 16),
  ];

  Widget _cropPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _aspectOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final (label, ratio) = _aspectOptions[i];
              final selected = _cropAspect == ratio;
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => setState(() {
                  _cropAspect = ratio;
                  if (ratio != null) {
                    _cropDraft = _fitAspect(ratio);
                  }
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.rotate_90_degrees_ccw),
              tooltip: 'Rotate left',
              onPressed: () => _rotate(-1),
            ),
            IconButton(
              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
              tooltip: 'Rotate right',
              onPressed: () => _rotate(1),
            ),
            IconButton(
              icon: const Icon(Icons.flip),
              tooltip: 'Flip horizontal',
              onPressed: () => _flip(horizontal: true),
            ),
            IconButton(
              icon: RotatedBox(
                  quarterTurns: 1, child: const Icon(Icons.flip)),
              tooltip: 'Flip vertical',
              onPressed: () => _flip(horizontal: false),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => setState(() {
                _cropDraft = const Rect.fromLTWH(0, 0, 1, 1);
                _cropAspect = null;
              }),
              child: const Text('Reset'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                _push();
                setState(() {
                  edit = edit.copyWith(crop: _cropDraft);
                  _tool = Tool.filters;
                });
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }

  /// Largest centered rect with the given canvas-space ratio.
  Rect _fitAspect(double ratio) {
    final imageAspect = _orientedWidth / _orientedHeight;
    double w = 1, h = 1;
    if (ratio > imageAspect) {
      h = imageAspect / ratio;
    } else {
      w = ratio / imageAspect;
    }
    return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
  }

  void _rotate(int direction) {
    _push();
    setState(() {
      final r = _cropDraft;
      _cropDraft = direction > 0
          ? Rect.fromLTWH(1 - r.bottom, r.left, r.height, r.width)
          : Rect.fromLTWH(r.top, 1 - r.right, r.height, r.width);
      final rc = edit.crop;
      final newCrop = direction > 0
          ? Rect.fromLTWH(1 - rc.bottom, rc.left, rc.height, rc.width)
          : Rect.fromLTWH(rc.top, 1 - rc.right, rc.height, rc.width);
      edit = edit.copyWith(
        quarterTurns: (edit.quarterTurns + direction) % 4,
        crop: newCrop,
      );
    });
  }

  void _flip({required bool horizontal}) {
    _push();
    setState(() {
      Rect flipRect(Rect r) => horizontal
          ? Rect.fromLTWH(1 - r.right, r.top, r.width, r.height)
          : Rect.fromLTWH(r.left, 1 - r.bottom, r.width, r.height);
      _cropDraft = flipRect(_cropDraft);
      // A horizontal screen flip corresponds to flipping the source axis
      // that currently maps to screen X.
      final swap = edit.quarterTurns.isOdd;
      final flipHNow = horizontal ^ swap ? !edit.flipH : edit.flipH;
      final flipVNow = horizontal ^ swap ? edit.flipV : !edit.flipV;
      edit = edit.copyWith(
        flipH: flipHNow,
        flipV: flipVNow,
        crop: flipRect(edit.crop),
      );
    });
  }

  // Draw --------------------------------------------------------------------

  Widget _drawPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: kPalette.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _colorDot(
              kPalette[i],
              selected: _brushColor == kPalette[i],
              onTap: () => setState(() => _brushColor = kPalette[i]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.line_weight, size: 18, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: _brushWidth,
                  min: 0.003,
                  max: 0.08,
                  onChanged: (v) => setState(() => _brushWidth = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo, size: 20),
                tooltip: 'Undo last stroke',
                onPressed: edit.strokes.isEmpty
                    ? null
                    : () {
                        _push();
                        setState(() => edit.strokes.removeLast());
                      },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Clear drawing',
                onPressed: edit.strokes.isEmpty
                    ? null
                    : () {
                        _push();
                        setState(() => edit.strokes.clear());
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _colorDot(Color color,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.lightBlueAccent : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }

  // Text --------------------------------------------------------------------

  OverlayItem? get _selected =>
      _selectedItem != null && _selectedItem! < edit.items.length
          ? edit.items[_selectedItem!]
          : null;

  Widget _textPanel() {
    final item = _selected?.kind == OverlayKind.text ? _selected : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: FilledButton.icon(
              onPressed: _addText,
              icon: const Icon(Icons.add),
              label: const Text('Add text'),
            ),
          )
        else ...[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: kTextFonts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final font = kTextFonts[i];
                return ChoiceChip(
                  label: Text(font,
                      style: GoogleFonts.getFont(font, fontSize: 13)),
                  selected: item.fontFamily == font,
                  onSelected: (_) {
                    _push();
                    setState(() => item.fontFamily = font);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final c in kPalette) ...[
                  _colorDot(
                    c,
                    selected: item.color == c,
                    onTap: () {
                      _push();
                      setState(() => item.color = c);
                    },
                  ),
                  const SizedBox(width: 10),
                ],
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Background'),
                  selected: item.hasBackground,
                  onSelected: (v) {
                    _push();
                    setState(() => item.hasBackground = v);
                  },
                ),
              ],
            ),
          ),
          _itemActionsRow(item),
        ],
      ],
    );
  }

  Widget _itemActionsRow(OverlayItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.zoom_out_map, size: 16, color: Colors.white70),
          Expanded(
            child: Slider(
              value: item.scale.clamp(0.2, 6.0),
              min: 0.2,
              max: 6,
              onChangeStart: (_) => _push(),
              onChanged: (v) => setState(() => item.scale = v),
            ),
          ),
          const Icon(Icons.rotate_right, size: 16, color: Colors.white70),
          Expanded(
            child: Slider(
              value: item.rotation.clamp(-3.14, 3.14),
              min: -3.14,
              max: 3.14,
              onChangeStart: (_) => _push(),
              onChanged: (v) => setState(() => item.rotation = v),
            ),
          ),
          if (item.kind == OverlayKind.text)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              tooltip: 'Edit text',
              onPressed: () => _editTextItem(_selectedItem!),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Delete',
            onPressed: () {
              _push();
              setState(() {
                edit.items.removeAt(_selectedItem!);
                _selectedItem = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addText() async {
    final text = await _promptText('Add text');
    if (text == null || text.trim().isEmpty) return;
    _push();
    setState(() {
      edit.items.add(OverlayItem(kind: OverlayKind.text, text: text.trim()));
      _selectedItem = edit.items.length - 1;
    });
  }

  Future<void> _editTextItem(int index) async {
    final item = edit.items[index];
    final text = await _promptText('Edit text', initial: item.text);
    if (text == null || text.trim().isEmpty) return;
    _push();
    setState(() => item.text = text.trim());
  }

  Future<String?> _promptText(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(hintText: 'Your text…'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Stickers ----------------------------------------------------------------

  Widget _stickerPanel() {
    final item = _selected?.kind == OverlayKind.sticker ? _selected : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: item == null ? 110 : 56,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: item == null ? 2 : 1,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: kStickers.length,
            itemBuilder: (context, i) => InkWell(
              onTap: () {
                _push();
                setState(() {
                  edit.items.add(OverlayItem(
                    kind: OverlayKind.sticker,
                    text: kStickers[i],
                  ));
                  _selectedItem = edit.items.length - 1;
                });
              },
              child: Center(
                child: Text(kStickers[i], style: const TextStyle(fontSize: 30)),
              ),
            ),
          ),
        ),
        if (item != null) _itemActionsRow(item),
      ],
    );
  }
}
