import 'package:flutter/material.dart';

import '../theme.dart';

class HeroSection extends StatefulWidget {
  const HeroSection({super.key});

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _typingAnimation;

  static const String _fullText = 'PIPSTATS';
  static const String _subtitle = 'LOCAL DEVICE STATISTICS';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _typingAnimation = IntTween(begin: 0, end: _fullText.length).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // CRT frame top
          Container(
            width: double.infinity,
            height: 2,
            color: ds.primary.withOpacity( 0.3),
          ),
          const SizedBox(height: 24),

          // Main title with typing animation
          AnimatedBuilder(
            animation: _typingAnimation,
            builder: (context, child) {
              final displayedText = _fullText.substring(0, _typingAnimation.value);
              return Column(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [
                        ds.primary,
                        ds.primary.withOpacity( 0.7),
                        ds.dim,
                      ],
                    ).createShader(bounds),
                    child: Text(
                      displayedText,
                      style: textTheme.displayLarge?.copyWith(
                        color: ds.primary,
                        fontSize: 56,
                        letterSpacing: 8,
                        fontWeight: FontWeight.normal,
                        shadows: [
                          Shadow(
                            color: ds.primary.withOpacity( 0.5),
                            blurRadius: 20,
                            offset: Offset.zero,
                          ),
                          Shadow(
                            color: ds.primary.withOpacity( 0.3),
                            blurRadius: 40,
                            offset: Offset.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Cursor blink during typing
                  if (_controller.isAnimating)
                    Container(
                      width: 12,
                      height: 48,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: ds.primary,
                        boxShadow: [
                          BoxShadow(
                            color: ds.primary.withOpacity( 0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            _subtitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: ds.dim,
              letterSpacing: 6,
              fontWeight: FontWeight.normal,
            ),
          ),

          const SizedBox(height: 8),

          // Tagline
          Text(
            'NO CLOUD • NO TRACKING • SEED VAULT READY',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ds.dim.withOpacity( 0.6),
              letterSpacing: 4,
            ),
          ),

          const SizedBox(height: 24),

          // CRT frame bottom
          Container(
            width: double.infinity,
            height: 2,
            color: ds.primary.withOpacity( 0.3),
          ),

          const SizedBox(height: 24),

          // Version badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: ds.primary.withOpacity( 0.5), width: 1),
              color: ds.panel,
            ),
            child: Text(
              'VERSION 1.1.0 • BUILT FOR SOLANA MOBILE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ds.dim,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}