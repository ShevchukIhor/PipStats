import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'components/hero_section.dart';
import 'components/feature_grid.dart';
import 'components/download_section.dart';
import 'components/footer.dart';
import 'pages/terms.dart';
import 'pages/privacy.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const PipStatsLandingApp());
}

class PipStatsLandingApp extends StatelessWidget {
  const PipStatsLandingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildDeviceStatsTheme(DeviceStatsColors.pipboy);
    return MaterialApp(
      title: 'PipStats — Local Device Statistics',
      debugShowCheckedModeBanner: false,
      theme: buildDeviceStatsTheme(DeviceStatsColors.pipboy),
      darkTheme: buildDeviceStatsTheme(DeviceStatsColors.pipboy),
      themeMode: ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('uk')],
      initialRoute: '/',
      routes: {
        '/': (context) => const LandingPage(),
        '/terms': (context) => const TermsPage(),
        '/privacy': (context) => const PrivacyPage(),
      },
      builder: (context, child) {
        return Theme(
          data: buildDeviceStatsTheme(DeviceStatsColors.pipboy),
          child: child!,
        );
      },
    );
  }
}

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Scaffold(
      backgroundColor: ds.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  children: [
                    const HeroSection(),
                    const FeatureGrid(),
                    const DownloadSection(),
                    const Footer(),
                  ],
                ),
              ),
            ],
          ),
          // CRT scanlines overlay
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ds.scanline.withOpacity( 0.1),
                    ds.scanline.withOpacity( 0.05),
                    ds.scanline.withOpacity( 0.1),
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
}