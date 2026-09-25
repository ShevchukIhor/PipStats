import 'package:flutter/material.dart';

/// Semantic colour tokens for the Device Stats (Pip-Boy) UI.
///
/// Exposed as a [ThemeExtension] so widgets resolve colours through
/// `Theme.of(context)` rather than hardcoded constants, enabling light and
/// high-contrast variants alongside the default terminal-green theme.
@immutable
class DeviceStatsColors extends ThemeExtension<DeviceStatsColors> {
  const DeviceStatsColors({
    required this.primary,
    required this.dim,
    required this.dark,
    required this.bg,
    required this.panel,
    required this.hintBg,
    required this.dangerBg,
    required this.dangerBorder,
    required this.dangerText,
    required this.dangerTextStrong,
    required this.battery,
    required this.scanline,
  });

  /// Primary "terminal" colour (text, active accents, fills).
  final Color primary;

  /// Dimmed secondary text.
  final Color dim;

  /// Dark accent: borders, subtle backgrounds, inactive fills.
  final Color dark;

  /// Page/scaffold background.
  final Color bg;

  /// Inset panel background (cards, rows).
  final Color panel;

  /// Warning/hint panel background.
  final Color hintBg;

  /// Dangerous-item panel background (delegations, close-authority risks).
  final Color dangerBg;

  /// Error/danger border colour.
  final Color dangerBorder;

  /// Error/danger text (labels).
  final Color dangerText;

  /// Strong error text (primary danger values).
  final Color dangerTextStrong;

  /// Battery-drain accent (amber), distinct from the terminal green primary.
  final Color battery;

  /// CRT scanline overlay stroke colour.
  final Color scanline;

  /// Whether to render the CRT treatment (scanlines, vignette, glow).
  ///
  /// Only the default Pip-Boy palette gets it. `highContrast` exists for
  /// legibility and `light` would look broken under scanlines, so both stay
  /// clean — which also leaves a one-tap escape from the CRT via the palette
  /// switcher when a dense table needs to be read.
  bool get crt => this == DeviceStatsColors.pipboy;

  @override
  DeviceStatsColors copyWith({
    Color? primary,
    Color? dim,
    Color? dark,
    Color? bg,
    Color? panel,
    Color? hintBg,
    Color? dangerBg,
    Color? dangerBorder,
    Color? dangerText,
    Color? dangerTextStrong,
    Color? battery,
    Color? scanline,
  }) {
    return DeviceStatsColors(
      primary: primary ?? this.primary,
      dim: dim ?? this.dim,
      dark: dark ?? this.dark,
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      hintBg: hintBg ?? this.hintBg,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      dangerText: dangerText ?? this.dangerText,
      dangerTextStrong: dangerTextStrong ?? this.dangerTextStrong,
      battery: battery ?? this.battery,
      scanline: scanline ?? this.scanline,
    );
  }

  @override
  DeviceStatsColors lerp(ThemeExtension<DeviceStatsColors>? other, double t) {
    if (other is! DeviceStatsColors) return this;
    return DeviceStatsColors(
      primary: Color.lerp(primary, other.primary, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      dark: Color.lerp(dark, other.dark, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      hintBg: Color.lerp(hintBg, other.hintBg, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      dangerTextStrong: Color.lerp(
        dangerTextStrong,
        other.dangerTextStrong,
        t,
      )!,
      battery: Color.lerp(battery, other.battery, t)!,
      scanline: Color.lerp(scanline, other.scanline, t)!,
    );
  }

  /// Default terminal-green ("Pip-Boy") palette on near-black.
  static const DeviceStatsColors pipboy = DeviceStatsColors(
    primary: Color(0xFF00FF00),
    dim: Color(0xFF00B84C),
    dark: Color(0xFF003B1A),
    bg: Color(0xFF020402),
    panel: Color(0xFF001100),
    hintBg: Color(0xFF0A1000),
    dangerBg: Color(0xFF2A0A00),
    dangerBorder: Color(0xFFFF4444),
    dangerText: Color(0xFFFF8888),
    dangerTextStrong: Color(0xFFFF6666),
    battery: Color(0xFFFFB300),
    scanline: Color(0x11000000),
  );

  /// High-contrast amber-on-black for accessibility (keeps the CRT look but
  /// with a brighter, warmer accent and stronger separations).
  static const DeviceStatsColors highContrast = DeviceStatsColors(
    primary: Color(0xFFFFCC00),
    dim: Color(0xFFFFAA33),
    dark: Color(0xFF332200),
    bg: Color(0xFF000000),
    panel: Color(0xFF1A1400),
    hintBg: Color(0xFF141000),
    dangerBg: Color(0xFF2E0000),
    dangerBorder: Color(0xFFFF2222),
    dangerText: Color(0xFFFF7777),
    dangerTextStrong: Color(0xFFFF5555),
    battery: Color(0xFFFF7A00),
    scanline: Color(0x11000000),
  );

  /// Light theme: readable dark-on-light with a green accent.
  static const DeviceStatsColors light = DeviceStatsColors(
    primary: Color(0xFF006400),
    dim: Color(0xFF2E7D32),
    dark: Color(0xFFA5D6A7),
    bg: Color(0xFFF4F7F0),
    panel: Color(0xFFE7EFE0),
    hintBg: Color(0xFFEFF3E8),
    dangerBg: Color(0xFFFDE7E7),
    dangerBorder: Color(0xFFC62828),
    dangerText: Color(0xFFC62828),
    dangerTextStrong: Color(0xFFB71C1C),
    battery: Color(0xFFE65100),
    scanline: Color(0x0A000000),
  );
}

/// Font sizes for the whole UI, in one place.
///
/// VT323 is a bitmap-style terminal face with a small x-height: it renders
/// noticeably smaller than its nominal size, so the previous 12-15px literals
/// read like ~10px of a normal font. These are the sizes the UI actually uses;
/// changing the scale is now a one-line edit rather than 81 scattered numbers.
class PipText {
  /// Row labels on the left of a key/value line.
  static const double label = 17;

  /// Body copy and secondary notes.
  static const double body = 18;

  /// Running prose: onboarding, disclosures, anything read a paragraph at a
  /// time rather than glanced at. The rest of the scale is built for key/value
  /// rows, where 18 is plenty; a wall of VT323 at that size is not.
  static const double reading = 20;

  /// The value on the right of a key/value line.
  static const double value = 18;

  /// Smaller supporting note under a value.
  static const double note = 16;

  /// `[ SECTION ]` headers.
  static const double heading = 24;

  /// Tab labels and the app bar.
  static const double title = 22;

  /// The single largest readout (battery percentage).
  static const double hero = 32;

  PipText._();
}

/// Short-hand accessor: `context.ds` returns the active [DeviceStatsColors].
extension DeviceStatsThemeX on BuildContext {
  DeviceStatsColors get ds =>
      Theme.of(this).extension<DeviceStatsColors>() ?? DeviceStatsColors.pipboy;
}

/// Builds the [ThemeData] for a palette.
ThemeData buildDeviceStatsTheme(DeviceStatsColors colors) {
  final isDark = colors.bg.computeLuminance() < 0.5;
  return ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.bg,
    fontFamily: 'VT323',
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: colors.primary,
      onPrimary: colors.bg,
      secondary: colors.dim,
      onSecondary: colors.bg,
      surface: colors.bg,
      onSurface: colors.primary,
      error: colors.dangerBorder,
      onError: colors.bg,
    ),
    extensions: [colors],
  );
}
