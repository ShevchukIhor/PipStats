import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

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
          'TERMS OF SERVICE',
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
                _sectionHeader(context, '1. ACCEPTANCE'),
                _bodyText(context,
                  'By downloading, installing, or using PipStats ("the App"), you agree to these Terms of Service '
                  '("Terms"). If you do not agree, do not use the App.'),
                _sectionHeader(context, '2. NO WARRANTY'),
                _bodyText(context,
                  'The App is provided "as is" without warranty of any kind, express or implied, including but not '
                  'limited to warranties of merchantability, fitness for a particular purpose, and non-infringement. '
                  'The developer does not warrant that the App will be uninterrupted, error-free, or free of harmful components.'),
                _sectionHeader(context, '3. DATA & PRIVACY'),
                _bodyText(context,
                  'PipStats stores all usage statistics locally on your device in an SQLite database. No usage data, '
                  'personal information, or analytics are transmitted to any external server. When you connect a Solana '
                  'wallet via Seed Vault or Mobile Wallet Adapter, the App performs read-only queries to public Solana '
                  'RPC endpoints using your public address. Private keys and seed phrases never leave the secure Seed '
                  'Vault hardware enclave.'),
                _sectionHeader(context, '4. SEED VAULT & WALLET CONNECTION'),
                _bodyText(context,
                  'The App integrates with Solana Mobile\'s Seed Vault via Mobile Wallet Adapter (MWA) for transaction '
                  'signing. You authorize each transaction explicitly through the Seed Vault UI (double-tap on Seeker). '
                  'The App never has access to your private keys or seed phrase.'),
                _sectionHeader(context, '5. THIRD-PARTY SERVICES'),
                _bodyText(context,
                  'The App may query the following public APIs:\n'
                  '• Solana RPC endpoints (public, rate-limited)\n'
                  '• Helius API (for token/NFT metadata, optional)\n'
                  '• AllDomains / ANS (for .skr domain resolution)\n'
                  'No personal data is sent to these services beyond your public wallet address.'),
                _sectionHeader(context, '6. SKR TOKEN TIPPING'),
                _bodyText(context,
                  'The App includes an optional tip feature using the SKR token (mint: SKRskrmtL83pcL4YqLWt6iPefDqwXQWHSw9S9vz94BZ). '
                  'Tips are sent from your wallet to the developer address via Seed Vault signing. '
                  'Tipping is entirely optional and not required for any App functionality.'),
                _sectionHeader(context, '7. DISCLAIMER OF LIABILITY'),
                _bodyText(context,
                  'In no event shall the developer be liable for any direct, indirect, incidental, special, consequential, '
                  'or punitive damages arising from your use of the App, including but not limited to loss of data, '
                  'financial loss, or damage to your device. Use at your own risk.'),
                _sectionHeader(context, '8. MODIFICATIONS'),
                _bodyText(context,
                  'The developer reserves the right to modify or discontinue the App at any time without notice. '
                  'Updates may be distributed via GitHub Releases, Solana dApp Store, or direct APK download.'),
                _sectionHeader(context, '9. GOVERNING LAW'),
                _bodyText(context,
                  'These Terms shall be governed by the laws of the jurisdiction in which the developer operates, '
                  'without regard to conflict of law principles.'),
                _sectionHeader(context, '10. CONTACT'),
                _bodyText(context,
                  'For questions about these Terms, contact the developer via GitHub: '
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