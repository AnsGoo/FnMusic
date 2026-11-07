/// The MusicFly palette: warm near-black, vermilion accent, cream lettering.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Touch devices handle volume with their hardware keys, so volume widgets
/// are hidden there.
///
/// OpenHarmony (HarmonyOS) reports its own operating system name ("ohos")
/// from dart:io, so it must be matched explicitly — isAndroid/isIOS are both
/// false there and the app would otherwise fall into the desktop layout
/// (fixed card widths, visible volume slider, 10 entries per section).
final bool isMobilePlatform =
    !kIsWeb &&
    (Platform.isAndroid || Platform.isIOS || Platform.operatingSystem == 'ohos');

class Mf {
  const Mf._();

  static const bg = Color(0xFF131010);
  static const surface = Color(0xFF1B1715);
  static const surfaceAlt = Color(0xFF241F1B);
  static const raised = Color(0xFF2C2521);
  static const border = Color(0xFF342C26);

  /// Slider grooves: a touch lighter than a border so a hairline still reads.
  static const track = Color(0xFF3E342C);

  static const accent = Color(0xFFE85C3A);
  static const accentHover = Color(0xFFF26E4D);
  static const accentWash = Color(0xFF3B211A);
  static const cream = Color(0xFFF6EFE3);

  static const text = Color(0xFFF4EEE4);
  static const textSoft = Color(0xFFC9BFB2);
  static const muted = Color(0xFF9A8F82);
  static const faint = Color(0xFF6B6259);
}

ThemeData buildMfTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Mf.bg,
    colorScheme: const ColorScheme.dark(
      primary: Mf.accent,
      onPrimary: Mf.cream,
      surface: Mf.surface,
      onSurface: Mf.text,
      surfaceContainerHighest: Mf.surfaceAlt,
      onSurfaceVariant: Mf.textSoft,
      outline: Mf.border,
      error: Mf.accent,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Mf.text,
      displayColor: Mf.text,
    ),
    dividerColor: Mf.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Mf.raised,
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Mf.raised,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: Mf.textSoft, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Mf.border.withValues(alpha: 0.9)),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
