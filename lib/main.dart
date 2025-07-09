import 'package:flutter/material.dart';
import 'package:hkray_vpn/screens/login_screen.dart';
import 'package:hkray_vpn/screens/vpn_wrapper_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Local fonts are now used instead of Google Fonts
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hkray_vpn/services/v2ray_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool? _isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    setState(() {
      _isLoggedIn = userId != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => V2RayService())],
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fa', 'IR'), // فارسی
        ],
        locale: const Locale('fa', 'IR'),
        debugShowCheckedModeBanner: false,
        title: 'HKRay VPN', // عنوان برنامه
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          // استفاده از فونت محلی Vazirmatn
          fontFamily: 'Vazirmatn',
          textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'Vazirmatn',
            bodyColor: Colors.black87,
            displayColor: Colors.black87,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor:
                Colors.blueAccent.shade700, // رنگ جذاب‌تر برای AppBar
            foregroundColor: Colors.white,
            centerTitle: true,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20), // گوشه‌های گرد برای AppBar
              ),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent, // رنگ دکمه‌ها
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // گوشه‌های گرد برای دکمه‌ها
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 3,
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                15,
              ), // گوشه‌های گرد برای Cardها
            ),
            margin: const EdgeInsets.all(8),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                12,
              ), // گوشه‌های گرد برای فیلدهای ورودی
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.blue.shade50.withOpacity(0.5),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 15,
            ),
          ),
        ),
        home: _isLoggedIn == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _isLoggedIn!
            ? const VpnWrapperScreen()
            : const LoginScreen(),
      ),
    );
  }
}
