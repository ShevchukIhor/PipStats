#!/usr/bin/env dart
// Asset generation script for PipStats landing page
// Run: dart run scripts/generate_assets.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main() async {
  final outputDir = Directory('web/landing/assets');
  await outputDir.create(recursive: true);
  await Directory('web/landing/assets/screenshots').create(recursive: true);

  print('Generating assets...');

  // Colors
  const primary = 0xFF00FF00;
  const bg = 0xFF020402;
  const panel = 0xFF001100;
  const dark = 0xFF003B1A;
  const battery = 0xFFFFB300;

  // 1. Generate master logo (SVG-like vector -> PNG 1024x1024)
  await _generateLogo(outputDir, primary, bg, panel, dark);

  // 2. Generate app icons from logo
  await _generateIcons(outputDir);

  // 3. Generate banners
  await _generateBanners(outputDir, primary, bg, panel, dark, battery);

  // 4. Generate placeholder screenshots
  await _generateScreenshots(outputDir);

  // 5. Copy favicon
  await _copyFavicon(outputDir);

  print('All assets generated successfully!');
}

/// Draw the PipStats logo: "PIPSTATS" in VT323 style with CRT frame
img.Image _drawLogo(int size, int primary, int bg, int panel, int dark) {
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(0x02, 0x04, 0x02));

  final centerX = size ~/ 2;
  final centerY = size ~/ 2;
  final fontSize = size ~/ 8;

  // CRT frame
  final framePadding = size ~/ 10;
  final frameRect = img.Rect.fromLTRB(
    framePadding,
    framePadding,
    size - framePadding,
    size - framePadding,
  );

  // Draw frame border
  img.drawRect(image, frameRect,
      color: img.ColorRgb8(0x00, 0x3B, 0x1A), thickness: size ~/ 80);

  // Inner panel
  final innerPadding = size ~/ 6;
  final innerRect = img.Rect.fromLTRB(
    innerPadding,
    innerPadding,
    size - innerPadding,
    size - innerPadding,
  );
  img.drawRect(image, innerRect,
      color: img.ColorRgb8(0x00, 0x11, 0x00),
      thickness: size ~/ 100);

  // Draw "PIPSTATS" text (simulated VT323 monospace)
  final text = 'PIPSTATS';
  final charWidth = fontSize * 0.6;
  final startX = centerX - (text.length * charWidth) ~/ 2;
  final textY = centerY + fontSize ~/ 2;

  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    final x = (startX + i * charWidth).round();
    // Draw character as blocky VT323-style
    _drawVT323Char(image, char, x, textY, fontSize, primary);
  }

  // Scanlines
  final scanlinePaint = img.Paint()..color = img.ColorRgba8(0, 0, 0, 18);
  for (int y = 0; y < size; y += 2) {
    img.drawLine(image, 0, y, size, y, scanlinePaint);
  }

  return image;
}

void _drawVT323Char(img.Image image, String char, int x, int y, int fontSize, int color) {
  final charImg = img.Image(width: fontSize, height: fontSize * 2);
  // Simple VT323-style character rendering
  // This is a simplified blocky font representation
  final pixelSize = (fontSize / 8).ceil();

  // For simplicity, draw a blocky representation
  final charRect = img.Rect.fromLTWH(x, y - fontSize, fontSize, fontSize * 2);
  img.drawRect(image, charRect, color: img.ColorRgb8(0x00, 0x3B, 0x1A));
  img.drawString(image, arial24, char,
      x: x + fontSize ~/ 4, y: y - fontSize + fontSize ~/ 2,
      color: img.ColorRgb8(
        (color >> 16) & 0xFF,
        (color >> 8) & 0xFF,
        color & 0xFF,
      ));
}

Future<void> _generateLogo(Directory outputDir, int primary, int bg, int panel, int dark) async {
  final logo = _drawLogo(1024, primary, bg, panel, dark);
  final file = File('${outputDir.path}/logo.png');
  await file.writeAsBytes(img.encodePng(logo));
  print('Generated logo.png (1024x1024)');
}

Future<void> _generateIcons(Directory outputDir) async {
  final logoFile = File('${outputDir.path}/logo.png');
  if (!await logoFile.exists()) return;

  final logoBytes = await logoFile.readAsBytes();
  final logo = img.decodePng(logoBytes)!;

  final sizes = [
    {'name': 'icon-192.png', 'size': 192, 'maskable': false},
    {'name': 'icon-512.png', 'size': 512, 'maskable': false},
    {'name': 'icon-maskable-192.png', 'size': 192, 'maskable': true},
    {'name': 'icon-maskable-512.png', 'size': 512, 'maskable': true},
  ];

  for (final spec in sizes) {
    final size = spec['size'] as int;
    final maskable = spec['maskable'] as bool;
    final name = spec['name'] as String;

    img.Image resized;
    if (maskable) {
      // Maskable: 40% safe zone (icon centered at 60%)
      final safeSize = (size * 0.6).round();
      resized = img.copyResize(logo, width: safeSize, height: safeSize);
      final canvas = img.Image(width: size, height: size);
      img.fill(canvas, color: img.ColorRgb8(0x02, 0x04, 0x02));
      // Center the icon
      final offset = (size - safeSize) ~/ 2;
      img.compositeImage(canvas, resized, dstX: offset, dstY: offset);
      resized = canvas;
    } else {
      resized = img.copyResize(logo, width: size, height: size);
    }

    final file = File('${outputDir.path}/$name');
    await file.writeAsBytes(img.encodePng(resized));
    print('Generated $name (${size}x${size})${maskable ? " [maskable]" : ""}');
  }
}

Future<void> _generateBanners(Directory outputDir, int primary, int bg, int panel, int dark, int battery) async {
  // Hero banner: 1280x720
  await _generateBanner(
    outputDir,
    'banner-hero.png',
    1280,
    720,
    primary,
    bg,
    panel,
    dark,
    battery,
    isHero: true,
  );

  // Store banner: 1024x500
  await _generateBanner(
    outputDir,
    'banner-store.png',
    1024,
    500,
    primary,
    bg,
    panel,
    dark,
    battery,
    isHero: false,
  );
}

Future<void> _generateBanner(
  Directory outputDir,
  String name,
  int width,
  int height,
  int primary,
  int bg,
  int panel,
  int dark,
  int battery,
  {required bool isHero},
) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0x02, 0x04, 0x02));

  final centerX = width ~/ 2;
  final centerY = height ~/ 2;

  // CRT scanlines
  final scanlinePaint = img.Paint()..color = img.ColorRgba8(0, 0, 0, 18);
  for (int y = 0; y < height; y += 2) {
    img.drawLine(image, 0, y, width, y, scanlinePaint);
  }

  // Grid pattern
  final gridPaint = img.Paint()..color = img.ColorRgba8(0, 0x3B, 0x1A, 30);
  final gridSize = 40;
  for (int x = 0; x < width; x += gridSize) {
    img.drawLine(image, x, 0, x, height, gridPaint);
  }
  for (int y = 0; y < height; y += gridSize) {
    img.drawLine(image, 0, y, width, y, gridPaint);
  }

  if (isHero) {
    // Hero: "PIPSTATS" large
    img.drawString(image, arial48, 'PIPSTATS',
        x: centerX - 180, y: centerY - 40,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));

    // Subtitle
    img.drawString(image, arial24, 'LOCAL DEVICE STATISTICS',
        x: centerX - 200, y: centerY + 30,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));

    // Tagline
    img.drawString(image, arial18, 'NO CLOUD  •  NO TRACKING  •  SEED VAULT READY',
        x: centerX - 250, y: centerY + 80,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
  } else {
    // Store banner: compact
    img.drawString(image, arial48, 'PIPSTATS',
        x: centerX - 150, y: centerY - 50,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));

    img.drawString(image, arial24, 'LOCAL DEVICE STATISTICS FOR SOLANA MOBILE',
        x: centerX - 280, y: centerY + 20,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));

    // Badges
    img.drawString(image, arial18, 'SEED VAULT  •  SKR TIPPING  •  NO CLOUD',
        x: centerX - 200, y: centerY + 70,
        color: img.ColorRgb8(0xFF, 0xB3, 0x00));
  }

  // Frame
  final frameRect = img.Rect.fromLTRB(2, 2, width - 2, height - 2);
  img.drawRect(image, frameRect,
      color: img.ColorRgb8(0x00, 0x3B, 0x1A), thickness: 2);

  final file = File('${outputDir.path}/$name');
  await file.writeAsBytes(img.encodePng(image));
  print('Generated $name (${width}x${height})');
}

Future<void> _generateScreenshots(Directory outputDir) async {
  // Generate placeholder screenshots with app-like content
  final screenshots = [
    {'name': 'screenshot-1.png', 'title': 'SYSTEM', 'subtitle': 'APP USAGE TRACKING'},
    {'name': 'screenshot-2.png', 'title': 'VAULT', 'subtitle': 'SEED VAULT INTEGRATION'},
    {'name': 'screenshot-3.png', 'title': 'SYSINFO', 'subtitle': 'BATTERY & DEVICE INFO'},
    {'name': 'screenshot-4.png', 'title': 'INFO', 'subtitle': 'TERMS • PRIVACY • ABOUT'},
  ];

  for (final spec in screenshots) {
    await _generateScreenshot(
      outputDir,
      spec['name']!,
      1280,
      720,
      spec['title']!,
      spec['subtitle']!,
    );
  }
}

Future<void> _generateScreenshot(
  Directory outputDir,
  String name,
  int width,
  int height,
  String title,
  String subtitle,
) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0x02, 0x04, 0x02));

  final centerX = width ~/ 2;
  final centerY = height ~/ 2;

  // CRT scanlines
  final scanlinePaint = img.Paint()..color = img.ColorRgba8(0, 0, 0, 18);
  for (int y = 0; y < height; y += 2) {
    img.drawLine(image, 0, y, width, y, scanlinePaint);
  }

  // Header bar
  final headerRect = img.Rect.fromLTRB(0, 0, width, 80);
  img.drawRect(image, headerRect, color: img.ColorRgb8(0x00, 0x11, 0x00));
  img.drawLine(image, 0, 80, width, 80,
      color: img.ColorRgb8(0x00, 0xFF, 0x00), thickness: 2);

  // Title
  img.drawString(image, arial24, title,
      x: 40, y: 30,
      color: img.ColorRgb8(0x00, 0xFF, 0x00));

  // Subtitle area
  img.drawString(image, arial18, subtitle,
      x: 40, y: 120,
      color: img.ColorRgb8(0x00, 0xB8, 0x4C));

  // Content area with sample data
  final contentY = 180;
  final lineHeight = 35;

  if (name == 'screenshot-1.png') {
    // SYSTEM tab mock
    final apps = [
      'com.android.chrome        2h 34m    12x',
      'com.termux                1h 12m     5x',
      'com.solflare.mobile       45m        3x',
      'com.phantom.app           32m        2x',
      'com.termux:api            18m        1x',
    ];
    for (int i = 0; i < apps.length; i++) {
      img.drawString(image, arial18, apps[i],
          x: 40, y: contentY + i * lineHeight,
          color: i < 3 ? img.ColorRgb8(0x00, 0xFF, 0x00) : img.ColorRgb8(0x00, 0xB8, 0x4C));
    }
  } else if (name == 'screenshot-2.png') {
    // VAULT tab mock
    img.drawString(image, arial18, 'CONNECTED: 5PpUJGRhM3FJN24mQD5wn...',
        x: 40, y: contentY,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));
    img.drawString(image, arial18, 'SOL BALANCE: 12.45 SOL',
        x: 40, y: contentY + lineHeight,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));
    img.drawString(image, arial18, 'EST. VALUE: ~$234.56',
        x: 40, y: contentY + 2 * lineHeight,
        color: img.ColorRgb8(0xFF, 0xB3, 0x00));
    img.drawString(image, arial18, '[ TOKENS ]  12 tokens found',
        x: 40, y: contentY + 3 * lineHeight,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
    img.drawString(image, arial18, '[ NFT ]  3 NFTs found',
        x: 40, y: contentY + 4 * lineHeight,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
  } else if (name == 'screenshot-3.png') {
    // SYSINFO tab mock
    final sysInfo = [
      'DEVICE: SM02E4072802182 (Solana Seeker)',
      'BATTERY: 2.95 mAh / 4.50 mAh (65%)',
      'CHARGE: 65% • DISCHARGING',
      'STORAGE: 42.3 GB / 128 GB',
      'MEMORY: 6.2 GB / 8 GB',
      'CPU: 8 cores @ 2.84 GHz',
    ];
    for (int i = 0; i < sysInfo.length; i++) {
      img.drawString(image, arial18, sysInfo[i],
          x: 40, y: contentY + i * lineHeight,
          color: img.ColorRgb8(0x00, 0xFF, 0x00));
    }
  } else if (name == 'screenshot-4.png') {
    // INFO tab mock
    img.drawString(image, arial18, '[ ABOUT ]',
        x: 40, y: contentY,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));
    img.drawString(image, arial18, 'Version: 1.1.0',
        x: 60, y: contentY + lineHeight,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
    img.drawString(image, arial18, '[ LEGAL ]',
        x: 40, y: contentY + 3 * lineHeight,
        color: img.ColorRgb8(0x00, 0xFF, 0x00));
    img.drawString(image, arial18, 'TERMS OF SERVICE  >',
        x: 60, y: contentY + 4 * lineHeight,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
    img.drawString(image, arial18, 'PRIVACY POLICY  >',
        x: 60, y: contentY + 5 * lineHeight,
        color: img.ColorRgb8(0x00, 0xB8, 0x4C));
  }

  // Tab bar at bottom
  final tabY = height - 100;
  img.drawLine(image, 0, tabY, width, tabY,
      color: img.ColorRgb8(0x00, 0xFF, 0x00), thickness: 2);

  final tabs = ['SYSTEM', 'VAULT', 'SYSINFO', 'INFO'];
  final tabWidth = width ~/ 4;
  for (int i = 0; i < tabs.length; i++) {
    final tabRect = img.Rect.fromLTRB(i * tabWidth, tabY, (i + 1) * tabWidth, height);
    final isActive = (name == 'screenshot-1.png' && i == 0) ||
        (name == 'screenshot-2.png' && i == 1) ||
        (name == 'screenshot-3.png' && i == 2) ||
        (name == 'screenshot-4.png' && i == 3);

    if (isActive) {
      img.fillRect(image, tabRect, color: img.ColorRgb8(0x00, 0x11, 0x00));
    }
    img.drawString(image, arial18, tabs[i],
        x: i * tabWidth + tabWidth ~/ 2 - 30, y: tabY + 30,
        color: isActive ? img.ColorRgb8(0x00, 0xFF, 0x00) : img.ColorRgb8(0x00, 0x3B, 0x1A));
  }

  // CRT scanlines
  final scanlinePaint = img.Paint()..color = img.ColorRgba8(0, 0, 0, 18);
  for (int y = 0; y < height; y += 2) {
    img.drawLine(image, 0, y, width, y, scanlinePaint);
  }

  final file = File('${outputDir.path}/screenshots/$name');
  await file.writeAsBytes(img.encodePng(image));
  print('Generated $name (${width}x${height})');
}

Future<void> _copyFavicon(Directory outputDir) async {
  final src = File('web/favicon.png');
  if (await src.exists()) {
    final dest = File('${outputDir.path}/favicon.png');
    await src.copy(dest.path);
    print('Copied favicon.png');
  }
}

// Simple PRNG for deterministic patterns
class _PseudoRandom {
  int _seed;
  _PseudoRandom(this._seed);
  bool nextBool() {
    _seed = (_seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_seed & 1) == 1;
  }
}