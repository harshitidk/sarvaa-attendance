import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';

/// What the person chose, which is not the same as what is on screen:
/// [AppThemeMode.system] follows the device.
enum AppThemeMode {
  system('system', 'System'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const AppThemeMode(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static AppThemeMode fromStorage(String? value) => values.firstWhere(
        (mode) => mode.storageKey == value,
        orElse: () => AppThemeMode.system,
      );
}

/// Owns the active palette and persists the choice.
///
/// Writes [AppColors.palette] before notifying, so any rebuild triggered by
/// this controller already sees the new tokens.
class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._(this._mode);

  static const _prefsKey = 'theme_mode';

  AppThemeMode _mode;

  AppThemeMode get mode => _mode;

  /// Restores the saved choice before the first frame.
  static Future<ThemeController> load() async {
    AppThemeMode mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      mode = AppThemeMode.fromStorage(prefs.getString(_prefsKey));
    } catch (_) {
      // A storage failure must not stop the app booting.
      mode = AppThemeMode.system;
    }
    final controller = ThemeController._(mode);
    WidgetsBinding.instance.addObserver(controller);
    controller._apply();
    return controller;
  }

  /// The brightness actually in effect right now.
  Brightness get brightness => switch (_mode) {
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
        AppThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      };

  bool get isDark => brightness == Brightness.dark;

  void _apply() {
    AppColors.palette =
        brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    _apply();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.storageKey);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  /// The device switched to or from dark mode while we were running.
  @override
  void didChangePlatformBrightness() {
    if (_mode != AppThemeMode.system) return;
    _apply();
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
