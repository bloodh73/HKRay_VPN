import 'package:HKRay_vpn/screens/splash_screen.dart';
import 'package:HKRay_vpn/services/v2ray_service.dart';
import 'package:HKRay_vpn/services/theme_notifier.dart'; // Import ThemeNotifier
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => V2RayService()),
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(),
        ), // Add ThemeNotifier
      ],
      child: Consumer<ThemeNotifier>(
        // Use Consumer to listen to ThemeNotifier
        builder: (context, themeNotifier, child) {
          // Set default theme to dark if not already set
          if (themeNotifier.themeMode == ThemeMode.system) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              themeNotifier.setThemeMode(ThemeMode.dark);
            });
          }

          return MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('fa', ''), Locale('en', '')],
            locale: const Locale('fa', ''),
            themeMode: themeNotifier.themeMode,
            debugShowCheckedModeBanner: false,

            // Light Theme
            theme: ThemeData(
              primaryColor: const Color(0xFF4A90E2),
              colorScheme: ColorScheme.fromSwatch().copyWith(
                primary: const Color(0xFF4A90E2),
                secondary: const Color.fromARGB(255, 80, 188, 227),
                surface: const Color(0xFFF0F2F5),
                background: const Color(0xFFE0E5EC),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Colors.black87,
                onBackground: Colors.black87,
                error: const Color(0xFFE04040),
              ),
              scaffoldBackgroundColor: const Color(0xFFE0E5EC),
              fontFamily: 'Vazirmatn',
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                titleTextStyle: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  elevation: 8,
                  textStyle: TextStyle(
                    fontFamily: 'Vazirmatn',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white,
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                hintStyle: TextStyle(
                  color: Colors.grey[500],
                  fontFamily: 'Vazirmatn',
                ),
                labelStyle: TextStyle(
                  color: Colors.grey[700],
                  fontFamily: 'Vazirmatn',
                ),
                prefixIconColor: Colors.grey[600],
              ),
              textTheme: TextTheme(
                displayLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 57,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                displayMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 45,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                displaySmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                headlineLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                headlineSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                titleMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                titleSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 16,
                  color: Colors.black87,
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  color: Colors.black87,
                ),
                bodySmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 12,
                  color: Colors.black54,
                ),
                labelLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                labelMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
                labelSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
            ),

            // Dark Theme
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primaryColor: const Color(0xFF1A2B3C),
              colorScheme: ColorScheme.fromSwatch(brightness: Brightness.dark)
                  .copyWith(
                    primary: const Color(0xFF3F82CD),
                    secondary: const Color(0xFF4ACDAB),
                    surface: const Color(0xFF2A3B4C),
                    background: const Color(0xFF121E2C),
                    onPrimary: Colors.white,
                    onSecondary: Colors.white,
                    onSurface: Colors.white70,
                    onBackground: Colors.white70,
                    error: const Color(0xFFE04040),
                  ),
              scaffoldBackgroundColor: const Color(0xFF121E2C),
              fontFamily: 'Vazirmatn',
              appBarTheme: AppBarTheme(
                backgroundColor: const Color(0xFF1A2B3C),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                titleTextStyle: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F82CD),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  elevation: 8,
                  textStyle: TextStyle(
                    fontFamily: 'Vazirmatn',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF2A3B4C),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                hintStyle: TextStyle(
                  color: Colors.grey[400],
                  fontFamily: 'Vazirmatn',
                ),
                labelStyle: TextStyle(
                  color: Colors.grey[300],
                  fontFamily: 'Vazirmatn',
                ),
                prefixIconColor: Colors.grey[400],
              ),
              textTheme: TextTheme(
                displayLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 57,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                displayMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 45,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                displaySmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                headlineLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                headlineMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                headlineSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                titleLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                titleMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
                titleSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
                bodyLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 16,
                  color: Colors.white70,
                ),
                bodyMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  color: Colors.white70,
                ),
                bodySmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 12,
                  color: Colors.white54,
                ),
                labelLarge: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                labelMedium: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
                labelSmall: TextStyle(
                  fontFamily: 'Vazirmatn',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.white54,
                ),
              ),
            ),
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
