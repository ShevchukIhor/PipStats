import 'package:flutter/material.dart';

import '../theme.dart';

class FeatureGrid extends StatelessWidget {
  const FeatureGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    final features = [
      _Feature(
        icon: Icons.track_changes_outlined,
        title: 'LOCAL TRACKING',
        description:
            'Foreground time & launch counts stored in local SQLite. No cloud, no analytics, no accounts. Your data never leaves the device.',
        accentColor: ds.primary,
      ),
      _Feature(
        icon: Icons.verified_outlined,
        title: 'SEED VAULT INTEGRATION',
        description:
            'Hardware-backed signing via Mobile Wallet Adapter. Connect Phantom, Solflare, or Seed Vault on Seeker. Supports .skr domains.',
        accentColor: ds.battery,
      ),
      _Feature(
        icon: Icons.battery_charging_full_outlined,
        title: 'BATTERY INSIGHTS',
        description:
            'Per-app battery drain estimation with rolling median capacity. Manual calibration, charging indicator, real-time drain bars.',
        accentColor: Color(0xFFFF7A00),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '[ FEATURES ]',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: features
                          .map((f) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: _FeatureCard(feature: f),
                                ),
                              ))
                          .toList(),
                    )
                  : Column(
                      children: features
                          .map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _FeatureCard(feature: f),
                              ))
                          .toList(),
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;

  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
  });
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;

  const _FeatureCard({required this.feature, super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.panel,
        border: Border.all(color: ds.dark, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon with glow
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: feature.accentColor.withOpacity( 0.15),
              border: Border.all(color: feature.accentColor.withOpacity( 0.3)),
            ),
            child: Icon(
              feature.icon,
              color: feature.accentColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            feature.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: feature.accentColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            feature.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}