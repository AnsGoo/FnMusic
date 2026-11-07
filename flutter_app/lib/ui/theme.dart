/// The Music Free palette, carried over from the old desktop theme so the
/// Flutter build keeps the same warm near-black, vermilion label and cream
/// lettering.
library;

import 'package:flutter/material.dart';

class Fn {
  const Fn._();

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

ThemeData buildFnTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Fn.bg,
    colorScheme: const ColorScheme.dark(
      primary: Fn.accent,
      onPrimary: Fn.cream,
      surface: Fn.surface,
      onSurface: Fn.text,
      surfaceContainerHighest: Fn.surfaceAlt,
      onSurfaceVariant: Fn.textSoft,
      outline: Fn.border,
      error: Fn.accent,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Fn.text,
      displayColor: Fn.text,
    ),
    dividerColor: Fn.border,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Fn.raised,
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: Fn.raised,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(color: Fn.textSoft, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Fn.border.withValues(alpha: 0.9)),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
