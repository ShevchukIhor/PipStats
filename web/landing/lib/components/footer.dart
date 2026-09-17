import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

class Footer extends StatelessWidget {
  const Footer({super.key});

  static const String _tipAddress = '5PpUJGRhM3FJN24mQD5wnKn6xSZLmA1ahPmouZvUFCHm';
  static const String _skrDomain = 'pipstats.skr';
  static const String _githubUrl = 'https://github.com/evil/device_stats';

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ds.dark, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legal links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(
                label: 'TERMS OF SERVICE',
                onTap: () => _launchUrl('/terms'),
              ),
              const SizedBox(width: 24),
              _FooterLink(
                label: 'PRIVACY POLICY',
                onTap: () => _launchUrl('/privacy'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(
                label: 'GITHUB',
                onTap: () => _launchUrl(_githubUrl),
              ),
              const SizedBox(width: 24),
              _FooterLink(
                label: '$_skrDomain',
                onTap: () => _launchUrl('https://alldomains.xyz'),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // SKR Tip address
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ds.hintBg,
              border: Border.all(color: ds.battery.withOpacity( 0.3), width: 1),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.attach_money_outlined, color: ds.battery, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'SUPPORT DEVELOPMENT (SKR)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: ds.battery,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _tipAddress,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ds.dim,
                    letterSpacing: 1,
                    fontFamily: 'VT323',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Copyright
          Center(
            child: Text(
              '2024 PIPSTATS • NO CLOUD • NO TRACKING • BUILT FOR SOLANA MOBILE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.3),
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: ds.dim,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (url.startsWith('/')) {
    // Internal navigation - handled by Flutter router
    return;
  }
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}