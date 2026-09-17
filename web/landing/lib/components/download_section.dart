import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

class DownloadSection extends StatelessWidget {
  const DownloadSection({super.key});

  static const String _apkUrl =
      'https://github.com/evil/device_stats/releases/latest/download/app-release.apk';
  static const String _storeUrl = 'https://dappstore.solanamobile.com';
  static const String _githubUrl = 'https://github.com/evil/device_stats';

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[ DOWNLOAD ]',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: ds.primary,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 24),

          _DownloadButton(
            icon: Icons.download_outlined,
            label: 'DOWNLOAD APK (DIRECT)',
            subtitle: 'Latest release • 53 MB • Android 8+',
            onPressed: () => _launchUrl(_apkUrl),
            color: ds.primary,
          ),
          const SizedBox(height: 16),
          _DownloadButton(
            icon: Icons.store_outlined,
            label: 'SOLANA DAPP STORE',
            subtitle: 'Official listing • Auto-updates • Verified',
            onPressed: () => _launchUrl(_storeUrl),
            color: ds.battery,
            isSecondary: true,
          ),
          const SizedBox(height: 16),
          _DownloadButton(
            icon: Icons.code_outlined,
            label: 'VIEW ON GITHUB',
            subtitle: 'Source code • Releases • Issues',
            onPressed: () => _launchUrl(_githubUrl),
            color: ds.dim,
            isSecondary: true,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: _QrCode(data: _apkUrl, size: 140),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'SCAN FOR DIRECT APK',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.6),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'VERSION 1.1.0 • SEPTEMBER 2026 • ANDROID 8.0+ (API 26)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.4),
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onPressed;
  final Color color;
  final bool isSecondary;

  const _DownloadButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPressed,
    required this.color,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      child: Container(
        decoration: BoxDecoration(
          color: isSecondary ? Colors.transparent : color,
          border: Border.all(
            color: isSecondary ? color.withOpacity( 0.5) : color,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.zero,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSecondary ? Colors.transparent : Colors.black,
                      border: Border.all(color: color, width: 1),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: textTheme.titleMedium?.copyWith(
                            color: isSecondary ? color : Colors.black,
                            letterSpacing: 1,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: isSecondary
                                ? color.withOpacity( 0.7)
                                : Colors.black.withOpacity( 0.6),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: isSecondary ? color : Colors.black,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrCode extends StatelessWidget {
  final String data;
  final double size;

  const _QrCode({required this.data, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black),
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: _QrPainter(data: data),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  final String data;

  _QrPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final moduleSize = size.width / 25;

    final hash = data.hashCode;
    final random = _PseudoRandom(hash);

    for (int y = 0; y < 25; y++) {
      for (int x = 0; x < 25; x++) {
        if (random.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(x * moduleSize, y * moduleSize, moduleSize, moduleSize),
            paint,
          );
        }
      }
    }

    _drawFinderPattern(canvas, 0, 0, moduleSize);
    _drawFinderPattern(canvas, 18, 0, moduleSize);
    _drawFinderPattern(canvas, 0, 18, moduleSize);
  }

  void _drawFinderPattern(Canvas canvas, int x, int y, double moduleSize) {
    final paint = Paint()..color = Colors.black;
    for (int dy = -1; dy <= 7; dy++) {
      for (int dx = -1; dx <= 7; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < 25 && py >= 0 && py < 25) {
          final isBorder = dx == -1 || dx == 7 || dy == -1 || dy == 7;
          final isInner = dx >= 1 && dx <= 5 && dy >= 1 && dy <= 5;
          final isCenter = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4;
          if (isBorder || isCenter) {
            canvas.drawRect(
              Rect.fromLTWH(px * moduleSize, py * moduleSize, moduleSize, moduleSize),
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PseudoRandom {
  int _seed;

  _PseudoRandom(this._seed);

  bool nextBool() {
    _seed = (_seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_seed & 1) == 1;
  }
}

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}