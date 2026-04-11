import 'package:flutter/material.dart';

/// Q-Loop design system — dark (default) + light palettes.
class AppColors {
  AppColors._();

  // ── Brand / Accent (theme-independent) ────────────────────────────────────
  static const Color primary    = Color(0xFF00D4AA);   // teal-green brand
  static const Color primaryDim = Color(0xFF00A882);
  static const Color accent     = Color(0xFF3B82F6);   // electric blue
  static const Color accentDim  = Color(0xFF1D4ED8);

  // ── Ghost Route (Mapbox overlay — same in both themes) ────────────────────
  static const Color ghostRoute      = Color(0x8000D4AA);
  static const Color ghostRouteSolid = Color(0xFF00D4AA);
  static const Color activeRoute     = Color(0xFF3B82F6);
  static const Color completedRoute  = Color(0xFF6B7280);
  static const Color stopMarker      = Color(0xFFF59E0B);

  // ── Semantic (same in both themes) ────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error   = Color(0xFFEF4444);
  static const Color info    = Color(0xFF3B82F6);

  // ── Dark palette ──────────────────────────────────────────────────────────
  static const Color scaffoldBg      = Color(0xFF0D1117);
  static const Color sidebarBg       = Color(0xFF161B22);
  static const Color cardBg          = Color(0xFF1C2128);
  static const Color surfaceAlt      = Color(0xFF21262D);
  static const Color textPrimary     = Color(0xFFE6EDF3);
  static const Color textSecondary   = Color(0xFF8B949E);
  static const Color textMuted       = Color(0xFF484F58);
  static const Color border          = Color(0xFF30363D);
  static const Color borderLight     = Color(0xFF3D444D);

  // ── Light palette ─────────────────────────────────────────────────────────
  static const Color lightScaffoldBg    = Color(0xFFF0F2F5);
  static const Color lightSidebarBg     = Color(0xFFFFFFFF);
  static const Color lightCardBg        = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt    = Color(0xFFF6F8FA);
  static const Color lightTextPrimary   = Color(0xFF0D1117);
  static const Color lightTextSecondary = Color(0xFF57606A);
  static const Color lightTextMuted     = Color(0xFF8C959F);
  static const Color lightBorder        = Color(0xFFD0D7DE);
  static const Color lightBorderLight   = Color(0xFFE1E4E8);

  // ── Theme-aware helpers ───────────────────────────────────────────────────

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardBg : lightCardBg;

  static Color sidebar(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? sidebarBg : lightSidebarBg;

  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? border : lightBorder;

  static Color labelText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textMuted : lightTextMuted;

  // ── Status chips ──────────────────────────────────────────────────────────
  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered': return success;
      case 'in_transit': return accent;
      case 'pending': return warning;
      case 'failed': return error;
      case 'returned': return textSecondary;
      default: return textMuted;
    }
  }
}
