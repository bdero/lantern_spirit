import 'package:flutter/material.dart';

/// Colors and text styles for the park-app shell around the character: a
/// quiet dark theme, so your friend's glow is the brightest thing on screen.
abstract final class Park {
  /// The screen behind everything: a deep navy-black.
  static const bg = Color(0xFF070A15);

  /// Cards, one step up, with a hairline edge.
  static const card = Color(0xFF10152A);
  static const cardTop = Color(0xFF151B33);
  static const line = Color(0xFF1E2643);

  /// A raised surface inside a card (tiles, wells).
  static const raised = Color(0xFF181F3A);

  /// Sheets that slide up over the screen.
  static const sheet = Color(0xFF0C1124);

  static const ink = Color(0xFFEEF1FB);
  static const inkMuted = Color(0xFF8B95BA);

  /// Ink for the few light surfaces (pills on photos, the primary button).
  static const onLight = Color(0xFF0B1022);

  /// The primary button: a cool white pill.
  static const button = Color(0xFFE8ECFA);

  static const gold = Color(0xFFF5B83D);
  static const good = Color(0xFF6BE0A5);
  static const goodBg = Color(0xFF12301F);
  static const night = Color(0xFF0A1024);
  static const glow = Color(0xFF8FD3FF);

  static const eyebrow = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.3,
    color: inkMuted,
  );
  static const title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: ink,
    height: 1.2,
  );
  static const body = TextStyle(fontSize: 15, color: ink, height: 1.35);
  static const tabular = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A card: dark surface, a faint lift at the top edge, a hairline border.
  static BoxDecoration cardDecoration({double radius = 18}) => BoxDecoration(
    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cardTop, card], stops: [0, 0.6]),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: line),
    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
  );
}
