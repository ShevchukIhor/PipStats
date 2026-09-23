#!/usr/bin/env dart-shell
// Asset generation script for PipStats landing page
// Run: dart run scripts/generate_assets.dart

import 'dart:io';

import 'package:image/image.dart' as img;

const String arial18 = 'arial18';
const String arial24 = 'arial24';
const String arial48 = 'arial48';

void main() async {
  final outputDir = Directory('web/landing/assets');
  await outputDir.create(recursive: true);
  await Directory('web/landing/assets/screenshots').create(recursive: true);

  // ignore: avoid_print
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

  // ignore: avoid_print
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
  
  // Draw frame border
  img.drawRect(image, 
      x1: framePadding, y1: framePadding, 
      x2: size - framePadding, y2: size - framePadding,
      color: img.ColorRgb8(0x00, 0x3B, 0x1A), thickness: size ~/ 80);

  // Inner panel
  final innerPadding = size ~/ 6;
  img.drawRect(image, 
      x1: innerPadding, y1: innerPadding, 
      x2: size - innerPadding, y2: size - innerPadding,
      color: img.ColorRgb8(0x00, 0x11, 0x00), thickness: size ~/ 100);

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
  for (int y = 0; y < size; y += 2) {
    img.drawLine(image, x1: 0, y1: y, x2: size, y2: y, color: img.ColorRgba8(0, 0, 0, 18));
  }

  return image;
}

void _drawVT323Char(img.Image image, String char, int x, int y, int fontSize, int color) {
  // Draw a blocky placeholder for the character to avoid font issues
  img.drawRect(image, 
      x1: x, y1: y - fontSize, 
      x2: x + fontSize, y2: y + fontSize,
      color: img.ColorRgb8(0x00, 0x3B, 0x1A));
  // Draw a small dot to represent the character position
  img.drawRect(image,
      x1: x + fontSize ~/ 3, y1: y - fontSize ~/ 3,
      x2: x + (fontSize * 2) ~/ 3, y2: y + fontSize ~/ 3,
      color: img.ColorRgb8((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF));
}

Future<void> _generateLogo(Directory outputDir, int primary, int bg, int panel, int dark) async {
  final logo = _drawLogo(1024, primary, bg, panel, dark);
  final file = File('${outputDir.path}/logo.png');
  await file.writeAsBytes(img.encodePng(logo));
    // ignore: avoid_print
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
    // ignore: avoid_print
    print('Generated $name (${size}x$size)${maskable ? " [maskable]" : ""}');
  }
}

Future<void> _generateBanners(Directory outputDir, int primary, int bg, int panel, int dark, int battery) async {
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
  {required bool isHero}
) async {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0x02, 0x04, 0x02));

  // Scanlines
  for (int y = 0; y < height; y += 2) {
    img.drawLine(image, x1: 0, y1: y, x2: width, y2: y, color: img.ColorRgba8(0, 0, 0, 18));
  }

  // Grid pattern
  final gridSize = 40;
  for (int x = 0; x < width; x += gridSize) {
    img.drawLine(image, x1: x, y1: 0, x2: x, y2: height, color: img.ColorRgba8(0, 0x3B, 0x1A, 30));
  }
  for (int y = 0; y < height; y += gridSize) {
    img.drawLine(image, x1: 0, y1: y, x2: width, y2: y, color: img.ColorRgba8(0, 0x3B, 0x1A, 30));
  }

  if (isHero) {
    _simulateDrawString(image, 'PIPSTATS', (width ~/ 2) - 180, (height ~/ 2) - 40, img.ColorRgb8(0x00, 0xFF, 0x00));

    _simulateDrawString(image, 'LOCAL DEVICE STATISTICS', (width ~/ 2) - 200, (height ~/ 2) + 30, img.ColorRgb8(0x00, 0xB8, 0x4C));

    _simulateDrawString(image, 'NO CLOUD  •  NO TRACKING  •  SEED VAULT READY', (width ~/ 2) - 250, (height ~/ 2) + 80, img.ColorRgb8(0x00, 0xB8, 0x4C));
  } else {
    _simulateDrawString(image, 'PIPSTATS', (width ~/ 2) - 150, (height ~/ 2) - 50, img.ColorRgb8(0x00, 0xFF, 0x00));

    _simulateDrawString(image, 'LOCAL DEVICE STATISTICS FOR SOLANA MOBILE', (width ~/ 2) - 280, (height ~/ 2) + 20, img.ColorRgb8(0x00, 0xB8, 0x4C));

    _simulateDrawString(image, 'SEED VAULT  •  SKR TIPPING  •  NO CLOUD', (width ~/ 2) - 200, (height ~/ 2) + 70, img.ColorRgb8(0xFF, 0xB3, 0x00));
  }

  // Frame
  img.drawRect(image, x1: 2, y1: 2, x2: width - 2, y2: height - 2,
      color: img.ColorRgb8(0x00, 0x3B, 0x1A), thickness: 2);

  final file = File('${outputDir.path}/$name');
  await file.writeAsBytes(img.encodePng(image));
    // ignore: avoid_print
    print('Generated $name (${width}x${height})');
}

Future<void> _generateScreenshots(Directory outputDir) async {
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

  // Header bar
  img.drawRect(image, x1: 0, y1: 0, x2: width, y2: 80, color: img.ColorRgb8(0x00, 0x11, 0x00));
  img.drawLine(image, x1: 0, y1: 80, x2: width, y2: 80, color: img.ColorRgb8(0x00, 0xFF, 0x00), thickness: 2);

  // Title
  _simulateDrawString(image, title, 40, 30, img.ColorRgb8(0x00, 0xFF, 0x00));

  // Subtitle area
  _simulateDrawString(image, subtitle, 40, 120, img.ColorRgb8(0x00, 0xB8, 0x4C));

  // Content area mock data
  final contentY = 180;
  final lineHeight = 35;

  if (name == 'screenshot-1.png') {
    final apps = [
      'com.android.chrome        2h 34m    12x',
      'com.termux                1h 12m     5x',
      'com.solflare.mobile       45m        3x',
      'com.phantom.app           32m        2x',
      'com.termux:api            18m        1x',
    ];
    for (int i = 0; i < apps.length; i++) {
      _simulateDrawString(image, apps[i], 40, contentY + i * lineHeight,
          i < 3 ? img.ColorRgb8(0x00, 0xFF, 0x00) : img.ColorRgb8(0x00, 0xB8, 0x4C));
    }
  } else if (name == 'screenshot-2.png') {
    _simulateDrawString(image, 'CONNECTED: 5PpUJGRhM3FJN24mQD5wn...', 40, contentY, img.ColorRgb8(0x00, 0xFF, 0x00));
    _simulateDrawString(image, 'SOL BALANCE: 12.45 SOL', 40, contentY + lineHeight, img.ColorRgb8(0x00, 0xFF, 0x00));
    _simulateDrawString(image, 'EST. VALUE: \$~234.56', 40, contentY + 2 * lineHeight, img.ColorRgb8(0xFF, 0xB3, 0x00));
  } else if (name == 'screenshot-3.png') {
    final sysInfo = [
      'DEVICE: SM02E4072802182 (Solana Seeker)',
      'BATTERY: 2.95 mAh / 4.50 mAh (65%)',
      'CHARGE: 65% • DISCHARGING',
      'STORAGE: 42.3 GB / 128 GB',
      'MEMORY: 6.2 GB / 8 GB',
    ];
    for (int i = 0; i < sysInfo.length; i++) {
      _simulateDrawString(image, sysInfo[i], 40, contentY + i * lineHeight, img.ColorRgb8(0x00, 0xFF, 0x00));
    }
  } else if (name == 'screenshot-4.png') {
    _simulateDrawString(image, '[ ABOUT ]', 40, contentY, img.ColorRgb8(0x00, 0xFF, 0x00));
    _simulateDrawString(image, 'Version: 1.1.0', 60, contentY + lineHeight, img.ColorRgb8(0x00, 0xB8, 0x4C));
  }

  // Tab bar at bottom
  final tabY = height - 100;
  img.drawLine(image, x1: 0, y1: tabY, x2: width, y2: tabY, color: img.ColorRgb8(0x00, 0xFF, 0x00), thickness: 2);

  final tabs = ['SYSTEM', 'VAULT', 'SYSINFO', 'INFO'];
  final tabWidth = width ~/ 4;
  for (int i = 0; i < tabs.length; i++) {
    final isActive = (name == 'screenshot-1.png' && i == 0) ||
        (name == 'screenshot-2.png' && i == 1) ||
        (name == 'screenshot-3.png' && i == 2) ||
        (name == 'screenshot-4.png' && i == 3);

    if (isActive) {
      img.drawRect(image, x1: i * tabWidth, y1: tabY, x2: (i + 1) * tabWidth, y2: height, color: img.ColorRgb8(0x00, 0x11, 0x00));
    }
    _simulateDrawString(image, tabs[i], i * tabWidth + tabWidth ~/ 2 - 30, tabY + 30,
        isActive ? img.ColorRgb8(0x00, 0xFF, 0x00) : img.ColorRgb8(0x00, 0x3B, 0x1A));
  }

  // Scanlines
  for (int y = 0; y < height; y += 2) {
    img.drawLine(image, x1: 0, y1: y, x2: width, y2: y, color: img.ColorRgba8(0, 0, 0, 18));
  }

  final file = File('${outputDir.path}/screenshots/$name');
  await file.writeAsBytes(img.encodePng(image));
    // ignore: avoid_print
    print('Generated $name (${width}x${height})');
}

Future<void> _copyFavicon(Directory outputDir) async {
  final src = File('web/favicon.png');
  if (await src.exists()) {
    final dest = File('${outputDir.path}/favicon.png');
    await src.copy(dest.path);
    // ignore: avoid_print
    print('Copied favicon.png');
  }
}

void _simulateDrawString(img.Image image, String text, int x, int y, img.Color color) {
  final charWidth = 10;
  final charHeight = 16;
  for (int i = 0; i < text.length; i++) {
    final charX = x + (i * charWidth);
    // Draw a small rectangle for the character "body"
    img.drawRect(image, 
        x1: charX, y1: y, 
        x2: charX + charWidth - 2, y2: y + charHeight, 
        color: color, thickness: 1);
    img.drawRect(image, 
        x1: charX + 2, y1: y + 4, 
        x2: charX + charWidth - 4, y2: y + charHeight - 4, 
        color: color);
  }
}