import 'package:flutter/material.dart';
import 'package:hkray_vpn/screens/login_screen.dart';
import 'package:hkray_vpn/screens/vpn_wrapper_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
        // تنظیمات محلی‌سازی برای پشتیبانی از زبان فارسی
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fa', ''), // فارسی
          Locale('en', ''), // انگلیسی
        ],
        locale: const Locale('fa', ''), // تنظیم زبان پیش‌فرض به فارسی

        debugShowCheckedModeBanner: false, // حذف بنر دیباگ
        theme: ThemeData(
          // پالت رنگی جدید و جذاب
          primaryColor: const Color(0xFF4A90E2), // آبی روشن
          colorScheme: ColorScheme.fromSwatch().copyWith(
            primary: const Color(0xFF4A90E2), // آبی روشن
            secondary: const Color(0xFF50E3C2), // فیروزه‌ای
            surface: const Color(0xFFF0F2F5), // خاکستری روشن برای پس‌زمینه کارت‌ها
            background: const Color(0xFFE0E5EC), // رنگ پس‌زمینه کلی
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: Colors.black87,
            onBackground: Colors.black87,
            error: const Color(0xFFE04040), // قرمز برای خطاها
          ),
          scaffoldBackgroundColor: const Color(0xFFE0E5EC), // پس‌زمینه کلی اسکفولد

          // فونت برنامه (فرض بر وجود فونت در پروژه)
          fontFamily: 'Vazirmatn', // نام فونت فارسی (مثلاً Vazirmatn)

          // تم AppBar
          appBarTheme: AppBarTheme(
            backgroundColor: const Color(0xFF4A90E2), // رنگ آبی روشن
            foregroundColor: Colors.white,
            elevation: 0, // حذف سایه
            centerTitle: true,
            titleTextStyle: TextStyle(
              fontFamily: 'Vazirmatn',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          // تم دکمه‌های ElevatedButton
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2), // رنگ آبی روشن
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), // گوشه‌های گردتر
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              elevation: 8, // سایه بیشتر
              textStyle: TextStyle(
                fontFamily: 'Vazirmatn',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // تم Card
          cardTheme: CardThemeData(
            elevation: 8, // سایه بیشتر
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20), // گوشه‌های بسیار گرد
            ),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white, // رنگ کارت‌ها
          ),

          // تم فیلدهای ورودی TextField
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), // گوشه‌های گرد
              borderSide: BorderSide.none, // بدون خط دور
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.9), // رنگ پر شده سفید با شفافیت
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

          // تم Text
          textTheme: TextTheme(
            displayLarge: TextStyle(fontFamily: 'Vazirmatn', fontSize: 57, fontWeight: FontWeight.bold, color: Colors.black87),
            displayMedium: TextStyle(fontFamily: 'Vazirmatn', fontSize: 45, fontWeight: FontWeight.bold, color: Colors.black87),
            displaySmall: TextStyle(fontFamily: 'Vazirmatn', fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87),
            headlineLarge: TextStyle(fontFamily: 'Vazirmatn', fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
            headlineMedium: TextStyle(fontFamily: 'Vazirmatn', fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
            headlineSmall: TextStyle(fontFamily: 'Vazirmatn', fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
            titleLarge: TextStyle(fontFamily: 'Vazirmatn', fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            titleMedium: TextStyle(fontFamily: 'Vazirmatn', fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
            titleSmall: TextStyle(fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
            bodyLarge: TextStyle(fontFamily: 'Vazirmatn', fontSize: 16, color: Colors.black87),
            bodyMedium: TextStyle(fontFamily: 'Vazirmatn', fontSize: 14, color: Colors.black87),
            bodySmall: TextStyle(fontFamily: 'Vazirmatn', fontSize: 12, color: Colors.black54),
            labelLarge: TextStyle(fontFamily: 'Vazirmatn', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
            labelMedium: TextStyle(fontFamily: 'Vazirmatn', fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
            labelSmall: TextStyle(fontFamily: 'Vazirmatn', fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black54),
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
