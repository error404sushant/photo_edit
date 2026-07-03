import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'editor/editor_screen.dart';

void main() {
  runApp(const PhotoEditApp());
}

class PhotoEditApp extends StatelessWidget {
  const PhotoEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'PhotoEdit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF101014),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = false;

  Future<void> _openEditor(ui.Image image) async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EditorScreen(image: image)));
  }

  Future<void> _pickImage() async {
    setState(() => _loading = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      await _openEditor(image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open image: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Renders a colorful demo photo so the editor can be tried without a file.
  Future<void> _useSample() async {
    setState(() => _loading = true);
    try {
      const w = 1600.0, h = 1000.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(w, h),
            const [Color(0xFF1A2980), Color(0xFF26D0CE), Color(0xFFFF8C42)],
            const [0.0, 0.55, 1.0],
          ),
      );
      // Sun
      canvas.drawCircle(
        const Offset(w * 0.72, h * 0.3),
        130,
        Paint()
          ..shader = ui.Gradient.radial(const Offset(w * 0.72, h * 0.3), 160, [
            const Color(0xFFFFF176),
            const Color(0x00FFF176),
          ]),
      );
      canvas.drawCircle(
        const Offset(w * 0.72, h * 0.3),
        90,
        Paint()..color = const Color(0xFFFFF59D),
      );
      // Mountain silhouettes
      final rng = math.Random(7);
      for (var layer = 0; layer < 3; layer++) {
        final baseY = h * (0.55 + layer * 0.14);
        final path = Path()
          ..moveTo(0, h)
          ..lineTo(0, baseY);
        var x = 0.0;
        while (x < w) {
          x += 120 + rng.nextDouble() * 160;
          path.lineTo(x, baseY - 60 - rng.nextDouble() * (140 - layer * 35));
          x += 100 + rng.nextDouble() * 140;
          path.lineTo(x, baseY + 20);
        }
        path
          ..lineTo(w, h)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = Color.lerp(
              const Color(0xFF0D1B4C),
              const Color(0xFF3E1F47),
              layer / 2,
            )!.withValues(alpha: 0.85),
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), h.toInt());
      await _openEditor(image);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFF00BCD4)],
                ),
              ),
              child: const Icon(
                Icons.photo_filter,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'PhotoEdit',
              style: GoogleFonts.poppins(
                fontSize: 34,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Filters · Adjustments · Crop · Draw · Text · Stickers',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 40),
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              FilledButton.icon(
                onPressed: _pickImage,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                ),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Open a photo'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _useSample,
                child: const Text('Try with a sample image'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
