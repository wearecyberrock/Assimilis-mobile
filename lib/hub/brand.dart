import 'package:flutter/material.dart';

/// Assimilis brand (AGENTS.md section 6): green #3d8c6e seven-armed tentacle icon on navy #171b26,
/// pixel-art mascot drawn with crisp edges (FilterQuality.none).
class AssimilisBrand {
  static const green = Color(0xFF3D8C6E);
  static const navy = Color(0xFF171B26);
  static const navyDeep = Color(0xFF121820);
  static const navyRaised = Color(0xFF1E2433);
  static const magenta = Color(0xFFE61478);

  static const icon = 'assets/brand/assimilis-app-icon-512.png';
  static const mascot = 'assets/brand/assimilis-mascot-256.png';

  /// The pixel mascot: never smoothed.
  static Widget mascotImage({double size = 96}) => Image.asset(
        mascot,
        width: size,
        height: size,
        filterQuality: FilterQuality.none,
        isAntiAlias: false,
      );
}
