import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persists the user's theme preference for the session.
/// Starts in dark mode (Q-Loop default).
final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.dark,
);
