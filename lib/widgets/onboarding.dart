import 'package:flutter/material.dart';

import 'package:pipstats/l10n/app_localizations.dart';
import 'package:pipstats/widgets/crt_overlay.dart' show pipGlow;
import 'package:pipstats/stats_service.dart';
import 'package:pipstats/theme.dart';

/// Public pages the last step links out to.
const _permissionsUrl = 'https://pipstats.pages.dev/permissions';
const _privacyUrl = 'https://pipstats.pages.dev/privacy';

/// First-run explanation of what the app measures and why it needs each
/// permission.
///
/// Blocking on purpose. The app used to open straight onto an empty screen
/// telling people to go to Settings, with a monitoring notification already
/// showing — an instruction, not a disclosure, which is what the dApp Store
/// rejected under PER-002. Nothing here is a wall: every required step can be
/// deferred, and the app stays usable without any of them, just empty.
class Onboarding extends StatefulWidget {
  const Onboarding({required this.onDone, super.key});

  /// Called once the user reaches the end, however many permissions they
  /// actually granted. Consent to monitor is recorded by the caller.
  final VoidCallback onDone;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> with WidgetsBindingObserver {
  int _step = 0;

  bool _usageGranted = false;
  bool _notifGranted = false;

  /// Set once the user has been to the Usage access screen and come back
  /// without the grant.
  ///
  /// Android blocks that switch outright for installs it considers sideloaded
  /// — the APK downloaded from a browser or a file manager — and the only clue
  /// is a dialog saying the app "was denied access". There is no API to ask
  /// whether the block is in force, so this infers it from the round trip
  /// failing, and then explains the way out. Nothing is shown until that
  /// happens, because most installs never hit it.
  bool _triedUsageGrant = false;

  /// True once a trip to the Usage access screen has come back empty-handed.
  bool get _usageBlocked => _triedUsageGrant && !_usageGranted;

  static const _lastStep = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshGrants();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Usage access and battery exemption are granted in a separate activity,
    // so the only moment we can notice is coming back from it.
    if (state == AppLifecycleState.resumed) _refreshGrants();
  }

  Future<void> _refreshGrants() async {
    final usage = await StatsService.instance.hasUsageAccess();
    final notif = await StatsService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _usageGranted = usage;
      _notifGranted = notif;
    });
  }

  /// Sends the user to the Usage access screen and remembers that they went.
  ///
  /// Coming back still un-granted is what [_usageBlocked] keys off.
  Future<void> _openUsageSettings() async {
    setState(() => _triedUsageGrant = true);
    await StatsService.openUsageSettings();
    await _refreshGrants();
  }

  void _next() {
    if (_step >= _lastStep) {
      widget.onDone();
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
      backgroundColor: ds.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.onboardTitle,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.heading,
                  letterSpacing: 3,
                  shadows: ds.crt ? pipGlow(ds.primary) : null,
                ),
              ),
              const SizedBox(height: 4),
              _progress(ds),
              const SizedBox(height: 20),
              Expanded(child: SingleChildScrollView(child: _body(ds, l10n))),
              const SizedBox(height: 12),
              _actions(ds, l10n),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// One dash per step, the current one filled.
  Widget _progress(DeviceStatsColors ds) {
    return Row(
      children: [
        for (var i = 0; i <= _lastStep; i++)
          Expanded(
            child: Container(
              height: 2,
              margin: EdgeInsets.only(right: i == _lastStep ? 0 : 4),
              color: i <= _step ? ds.primary : ds.dark,
            ),
          ),
      ],
    );
  }

  Widget _body(DeviceStatsColors ds, AppLocalizations l10n) {
    return switch (_step) {
      0 => _section(
          ds,
          heading: l10n.onboardIntroHeading,
          paragraphs: [l10n.onboardIntroBody],
        ),
      1 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(
              ds,
              heading: l10n.onboardUsageHeading,
              badge: _usageGranted ? l10n.onboardGranted : l10n.onboardRequired,
              badgeOk: _usageGranted,
              paragraphs: [
                l10n.usageDisclosureWhat,
                l10n.usageDisclosureWhy,
                l10n.usageDisclosureWhere,
                l10n.usageDisclosureRevoke,
              ],
            ),
            if (_usageBlocked) _restrictedHelp(ds, l10n),
          ],
        ),
      2 => _section(
          ds,
          heading: l10n.onboardNotifHeading,
          badge: _notifGranted ? l10n.onboardGranted : l10n.onboardRequired,
          badgeOk: _notifGranted,
          paragraphs: [l10n.onboardNotifBody],
        ),
      3 => _section(
          ds,
          heading: l10n.onboardBatteryHeading,
          badge: l10n.onboardOptional,
          paragraphs: [l10n.onboardBatteryBody],
        ),
      _ => _section(
          ds,
          heading: l10n.onboardDoneHeading,
          paragraphs: [l10n.onboardDoneBody],
          links: {
            l10n.usageDisclosureMore: _permissionsUrl,
            l10n.onboardPrivacyLink: _privacyUrl,
          },
        ),
    };
  }

  /// Shown only after a trip to Settings came back without the grant.
  ///
  /// Every app that measures screen time needs this one switch, and Android
  /// blocks it silently for sideloaded installs, so the usual outcome is
  /// someone concluding the app is broken. Spelling the way out is the whole
  /// point of this block.
  Widget _restrictedHelp(DeviceStatsColors ds, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ds.dangerBg,
        border: Border.all(color: ds.dangerBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.onboardRestrictedHeading,
            style: TextStyle(
              color: ds.dangerTextStrong,
              fontSize: PipText.heading,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.onboardRestrictedBody,
            style: TextStyle(
              color: ds.dangerText,
              fontSize: PipText.reading,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _button(ds, l10n.onboardOpenAppInfo, StatsService.openOwnAppInfo,
              filled: false),
        ],
      ),
    );
  }

  Widget _section(
    DeviceStatsColors ds, {
    required String heading,
    required List<String> paragraphs,
    String? badge,
    bool badgeOk = false,
    Map<String, String> links = const {},
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                heading,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.heading,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (badge != null)
              Text(
                badge,
                style: TextStyle(
                  color: badgeOk ? ds.primary : ds.dim,
                  fontSize: PipText.note,
                  letterSpacing: 2,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              p,
              style: TextStyle(
                color: ds.primary,
                fontSize: PipText.reading,
                height: 1.5,
              ),
            ),
          ),
        for (final entry in links.entries)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => StatsService.openUrl(entry.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                entry.key,
                style: TextStyle(
                  color: ds.primary,
                  fontSize: PipText.reading,
                  decoration: TextDecoration.underline,
                  decorationColor: ds.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _actions(DeviceStatsColors ds, AppLocalizations l10n) {
    final grant = switch (_step) {
      1 when !_usageGranted => (l10n.grantAccess, _openUsageSettings),
      2 when !_notifGranted => (
          l10n.onboardAllow,
          StatsService.requestNotificationPermission,
        ),
      3 => (l10n.onboardAllow, StatsService.requestIgnoreBatteryOptimizations),
      _ => null,
    };

    return Row(
      children: [
        if (_step > 0) ...[
          SizedBox(
            width: 150,
            child: _button(ds, l10n.onboardBack, _back, filled: false),
          ),
          const SizedBox(width: 10),
        ],
        if (grant != null) ...[
          Expanded(child: _button(ds, grant.$1, () async {
            await grant.$2();
            await _refreshGrants();
          }, filled: true)),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _button(
            ds,
            _step >= _lastStep
                ? l10n.onboardStart
                : (grant != null ? l10n.onboardLater : l10n.onboardNext),
            _next,
            filled: grant == null,
          ),
        ),
      ],
    );
  }

  Widget _button(
    DeviceStatsColors ds,
    String label,
    VoidCallback onTap, {
    required bool filled,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? ds.primary : Colors.transparent,
          border: Border.all(color: ds.primary, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? ds.bg : ds.primary,
            fontSize: PipText.reading,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
