import 'package:flutter/material.dart';

/// Semantic colour tokens for the PipStats landing page (Pip-Boy/CRT aesthetic).
/// Mirrors the app's DeviceStatsColors for consistency.
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

  final Color primary;
  final Color dim;
  final Color dark;
  final Color bg;
  final Color panel;
  final Color hintBg;
  final Color dangerBg;
  final Color dangerBorder;
  final Color dangerText;
  final Color dangerTextStrong;
  final Color battery;
  final Color scanline;

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
      dangerTextStrong: Color.lerp(dangerTextStrong, other.dangerTextStrong, t)!,
      battery: Color.lerp(battery, other.battery, t)!,
      scanline: Color.lerp(scanline, other.scanline, t)!,
    );
  }

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

extension DeviceStatsThemeX on BuildContext {
  DeviceStatsColors get ds =>
      Theme.of(this).extension<DeviceStatsColors>() ?? DeviceStatsColors.pipboy;
}

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
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontFamily: 'VT323', fontSize: 56, letterSpacing: 4),
      displayMedium: TextStyle(fontFamily: 'VT323', fontSize: 40, letterSpacing: 3),
      displaySmall: TextStyle(fontFamily: 'VT323', fontSize: 32, letterSpacing: 2),
      headlineLarge: TextStyle(fontFamily: 'VT323', fontSize: 28, letterSpacing: 2),
      headlineMedium: TextStyle(fontFamily: 'VT323', fontSize: 24, letterSpacing: 2),
      headlineSmall: TextStyle(fontFamily: 'VT323', fontSize: 20, letterSpacing: 2),
      titleLarge: TextStyle(fontFamily: 'VT323', fontSize: 18, letterSpacing: 1),
      titleMedium: TextStyle(fontFamily: 'VT323', fontSize: 16, letterSpacing: 1),
      titleSmall: TextStyle(fontFamily: 'VT323', fontSize: 14, letterSpacing: 1),
      bodyLarge: TextStyle(fontFamily: 'VT323', fontSize: 18, letterSpacing: 1),
      bodyMedium: TextStyle(fontFamily: 'VT323', fontSize: 16, letterSpacing: 1),
      bodySmall: TextStyle(fontFamily: 'VT323', fontSize: 14, letterSpacing: 1),
      labelLarge: TextStyle(fontFamily: 'VT323', fontSize: 14, letterSpacing: 1),
      labelMedium: TextStyle(fontFamily: 'VT323', fontSize: 12, letterSpacing: 1),
      labelSmall: TextStyle(fontFamily: 'VT323', fontSize: 10, letterSpacing: 1),
    ).apply(fontFamily: 'VT323'),
  );
}