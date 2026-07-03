# PhotoEdit 📸

A full-featured photo editing app built with **Flutter**, running entirely in the browser (Flutter Web). No uploads, no backend — every edit happens on your device.

## ✨ Features

| Tool | What it does |
|------|--------------|
| **Looks** | 16 professionally-tuned templates (Auto Pop, Golden Hour, Portrait Glow, Teal & Orange, HDR Crisp, Moody, Film 35mm, Dreamy, Night Boost…) that apply a complete style — filter, tone, color and vignette — in one tap, with live previews of your photo |
| **Filters** | 16 one-tap presets (Vivid, Pop, Warm, Golden, Cool, Arctic, Cinema, Retro, Fade, Mono, Noir, Silver, Sepia, Rose, Forest) with live thumbnails and an intensity slider |
| **Adjust** | Brightness, Exposure, Contrast, Saturation, Warmth, Tint, Hue, Fade, Vignette, Blur — each with its own slider and per-control reset |
| **AI Enhance** | One-tap auto-fix (the ✨ wand in the top bar). Analyzes the photo's histogram — exposure, shadows, tonal spread, color dullness, color cast — and applies balanced corrections automatically |
| **Selective** | Fix just one part of the photo (e.g. a face in shadow). Place a feathered spot, drag it over the area, resize it, then adjust brightness/exposure/contrast/saturation/warmth for that region only |
| **Crop & Rotate** | Freeform crop with rule-of-thirds grid, aspect-ratio locks (1:1, 4:3, 3:4, 16:9, 9:16), 90° rotation, horizontal/vertical flip |
| **Draw** | Freehand brush with 10 colors and adjustable stroke width |
| **Text** | Add text overlays — 7 fonts, 10 colors, optional background chip. Drag to move, sliders for size & rotation, double-click to re-edit |
| **Stickers** | 40 emoji stickers, draggable and resizable |
| **History** | Undo / redo (up to 60 steps), hold the 👁 eye icon to compare with the original, one-tap reset |
| **Export** | Saves a full-resolution PNG straight to your downloads |

## 🚀 Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.19+ (stable channel)
- Chrome (for running on web)

### Run locally

```bash
git clone https://github.com/error404sushant/photo_edit.git
cd photo_edit
flutter pub get
flutter run -d chrome
```

### Build for production

```bash
flutter build web --release
```

The deployable bundle lands in `build/web/` — host it on any static server (GitHub Pages, Firebase Hosting, Netlify, nginx…). To try it quickly:

```bash
cd build/web
python3 -m http.server 8080
# open http://localhost:8080
```

## 📖 How to use

1. **Open a photo** — pick an image from your device, or click *Try with a sample image* to explore instantly.
2. **Quick fix** — tap the ✨ **wand** in the top bar. AI Enhance reads the photo's histogram and auto-balances exposure, contrast, color and warmth. Hold the 👁 icon to compare before/after; undo if you don't like it.
3. **Fine-tune** — open **Adjust** and drag any slider. A yellow dot marks the controls you've touched; the ↻ button resets one control.
4. **Fix a region** — open **Selective** → *Add spot* → drag the dashed circle over the area (a dark face, a blown-out window…) → tune the sliders. *Size* and *Feather* control the reach and softness. Add as many spots as you need.
5. **Frame it** — open **Crop**, drag the corners or pick a ratio chip, rotate/flip, then hit *Apply*.
6. **Decorate** — scribble with **Draw**, add captions with **Text** (double-click any text to edit it), drop **Stickers**.
7. **Save** — the *Save* button exports a full-resolution PNG with every edit baked in.

## 🏗 Architecture

```
lib/
├── main.dart                  # App entry, theme, home screen
├── models/
│   └── editor_models.dart     # Edit state, adjustments, spots, overlays, undo snapshots
├── editor/
│   ├── editor_screen.dart     # Editor UI: canvas, tool tabs, panels
│   ├── painters.dart          # Canvas painters: filtered image, selective spots, vignette, strokes
│   └── crop_overlay.dart      # Interactive crop rectangle
└── utils/
    ├── matrices.dart          # 4x5 color-matrix math for all filters & adjustments
    └── saver.dart             # PNG download (web)
```

- All color work is done with composable **4×5 color matrices** rendered on the GPU — sliders stay real-time even on large photos.
- Selective spots re-paint the image through the spot's own matrix, masked by a **feathered radial gradient** (`saveLayer` + `dstIn`).
- Export captures the canvas via `RepaintBoundary.toImage` at the photo's native resolution.

## 👤 Author

**error404sushant**

## 📄 License

Open source — free to use, modify and share.
