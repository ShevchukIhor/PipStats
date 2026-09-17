import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: ds.bg,
      appBar: AppBar(
        backgroundColor: ds.dark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: ds.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'PRIVACY POLICY',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: ds.primary,
            letterSpacing: 4,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(context, '1. DATA CONTROLLER'),
                _bodyText(context,
                  'PipStats ("the App") is developed and maintained by the individual developer '
                  'operating under the GitHub handle "evil". Contact: https://github.com/evil/device_stats'),
                _sectionHeader(context, '2. DATA COLLECTED'),
                _bodyText(context,
                  'The App collects and stores the following data locally on your device:\n\n'
                  '• Application usage statistics: foreground time (milliseconds) and launch counts per package\n'
                  '• Battery samples: charge counter (µAh), current (µA), charging state, timestamps\n'
                  '• Wallet connection: public Solana address (base58) and optional account label\n'
                  '• Calibration data: manually entered battery capacity (mAh)\n\n'
                  'No personal identifiers (name, email, phone, location) are collected. No analytics, '
                  'crash reporting, or telemetry are implemented.'),
                _sectionHeader(context, '3. PURPOSE OF PROCESSING'),
                _bodyText(context,
                  'Data is processed solely for:\n'
                  '• Displaying your app usage statistics (foreground time, launches)\n'
                  '• Estimating per-app battery drain\n'
                  '• Showing wallet balance and token/NFT holdings (read-only)\n'
                  '• Enabling optional SKR token tipping via Seed Vault'),
                _sectionHeader(context, '4. STORAGE & SECURITY'),
                _bodyText(context,
                  'All data is stored in a local SQLite database (sqflite) on your device\'s internal storage. '
                  'The database is not backed up to cloud services. The App does not implement any network '
                  'sync for user data. Wallet private keys and seed phrases never leave the Seed Vault '
                  'hardware enclave; the App only receives signed transaction results.'),
                _sectionHeader(context, '5. DATA SHARING'),
                _bodyText(context,
                  'Your data is never sold, rented, or shared with third parties. The only external '
                  'communication is:\n'
                  '• Read-only RPC calls to public Solana endpoints (your public address)\n'
                  '• Optional Helius API calls for token/NFT metadata (public address only)\n'
                  '• .skr domain resolution via AllDomains (public domain query)\n\n'
                  'No usage statistics, battery data, or calibration data ever leaves your device.'),
                _sectionHeader(context, '6. SEED VAULT & WALLET AUTHORIZATION'),
                _bodyText(context,
                  'When you connect a wallet, the App uses Mobile Wallet Adapter (MWA) to request '
                  'authorization from Seed Vault. You explicitly approve each connection and each '
                  'transaction via the Seed Vault UI (double-tap on Seeker). The App never sees, '
                  'stores, or transmits your private keys, seed phrase, or signing credentials.'),
                _sectionHeader(context, '7. DATA RETENTION'),
                _bodyText(context,
                  'Data persists until you manually delete it:\n'
                  '• Usage statistics: cleared via "RESET STATTS" button or app uninstall\n'
                  '• Battery samples: cleared via app uninstall\n'
                  '• Wallet connection: cleared via "REMOVE" button or app uninstall\n'
                  '• Calibration: persists across sessions until manually reset'),
                _sectionHeader(context, '8. YOUR RIGHTS'),
                _bodyText(context,
                  'Since all data stays on your device, you have full control:\n'
                  '• Access: View all data in the App\'s UI (SYSTEM, SYSINFO, VAULT tabs)\n'
                  '• Rectification: Manually calibrate battery capacity\n'
                  '• Erasure: Use "RESET STATS" or uninstall the App\n'
                  '• Portability: Data is in standard SQLite format (accessible via adb)'),
                _sectionHeader(context, '9. THIRD-PARTY SERVICES'),
                _bodyText(context,
                  'The App may communicate with:\n'
                  '• Public Solana RPC endpoints (Solana Foundation, Helius, etc.)\n'
                  '• Helius API (optional, for enhanced token/NFT metadata)\n'
                  '• AllDomains / ANS (for .skr domain resolution)\n\n'
                  'These services receive only your public wallet address or domain query. '
                  'Review their privacy policies separately.'),
                _sectionHeader(context, '10. CHILDREN\'S PRIVACY'),
                _bodyText(context,
                  'The App is not directed at children under 13 (or applicable age). No personal data '
                  'is collected from children. If you believe a child has provided data, contact the '
                  'developer for immediate deletion.'),
                _sectionHeader(context, '11. CHANGES TO THIS POLICY'),
                _bodyText(context,
                  'This Privacy Policy may be updated. Changes will be reflected in the App\'s INFO tab '
                  'and on the landing page. Continued use constitutes acceptance of the updated policy.'),
                _sectionHeader(context, '12. CONTACT'),
                _bodyText(context,
                  'For privacy inquiries, contact the developer via GitHub: '
                  'https://github.com/evil/device_stats'),

                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'LAST UPDATED: SEPTEMBER 2026',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity( 0.4),
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
          // CRT scanlines overlay
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).extension<DeviceStatsColors>()!.scanline.withOpacity( 0.1),
                    Theme.of(context).extension<DeviceStatsColors>()!.scanline.withOpacity( 0.05),
                    Theme.of(context).extension<DeviceStatsColors>()!.scanline.withOpacity( 0.1),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    final ds = Theme.of(context).extension<DeviceStatsColors>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: ds.primary,
          letterSpacing: 3,
        ),
      ),
    );
  }

  Widget _bodyText(BuildContext context, String text) {
    final ds = Theme.of(context).extension<DeviceStatsColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: ds.dim,
          height: 1.6,
        ),
      ),
    );
  }
}