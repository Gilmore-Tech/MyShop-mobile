import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Theme Notifier ────────────────────────────────────────────────────────────
// Persists the user's chosen ThemeMode to SharedPreferences.
// Key: 'myshop_theme_dark' (bool)
//
// NOT autoDispose — lives for the full app lifetime so MaterialApp.router can
// watch it without losing state on navigation.

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _load();
  }

  static const _kKey = 'myshop_theme_dark';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_kKey) ?? false;
    if (mounted) state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, mode == ThemeMode.dark);
  }
}

final themeNotifierProvider =
    StateNotifierProvider<ThemeNotifier, ThemeMode>((_) => ThemeNotifier());
