// lib/services/theme_notifier.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Default to system theme

  ThemeMode get themeMode => _themeMode;

  ThemeNotifier() {
    _loadThemeMode(); // Load theme preference when initialized
  }

  // Loads the saved theme mode from SharedPreferences
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode');
    if (themeIndex != null) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      // If no theme is saved, check system brightness
      final Brightness platformBrightness =
          WidgetsBinding.instance.window.platformBrightness;
      _themeMode = platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    notifyListeners();
  }

  // Toggles the theme mode and saves the preference
  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    await prefs.setInt(
      'theme_mode',
      _themeMode.index,
    ); // Save the index of the enum
    notifyListeners(); // Notify listeners to rebuild widgets
  }

  // Sets the theme mode to a specific value
  void setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme_mode', _themeMode.index);
      notifyListeners();
    }
  }
}
