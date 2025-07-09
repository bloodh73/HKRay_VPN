// فایل: vpn_wrapper_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class VpnWrapperScreen extends StatefulWidget {
  const VpnWrapperScreen({super.key});

  @override
  State<VpnWrapperScreen> createState() => _VpnWrapperScreenState();
}

class _VpnWrapperScreenState extends State<VpnWrapperScreen> {
  // متد fetch به بیرون از initState منتقل شد
  late Future<List<V2RayConfig>> _v2rayConfigFuture;
  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

  @override
  void initState() {
    super.initState();
    // فراخوانی متد fetch در initState تا FutureBuilder آن را اجرا کند
    _v2rayConfigFuture = _fetchV2RayConfig();
  }

  void _retryFetch() {
    // این متد برای دکمه "تلاش مجدد" استفاده می‌شود
    setState(() {
      _v2rayConfigFuture = _fetchV2RayConfig();
    });
  }

  Future<List<V2RayConfig>> _fetchV2RayConfig() async {
    try {
      final url = Uri.parse('$_apiBaseUrl?action=getSubscription');
      final response = await http.get(url);
      print('API Response: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          final List<dynamic> shareLinks = responseData['share_links'] ?? [];
          final configs = _parseShareLinks(shareLinks);

          if (configs.isNotEmpty) {
            return configs;
          } else {
            // اگر کانفیگی یافت نشد، یک خطا ایجاد می‌کنیم
            throw Exception('هیچ کانفیگ معتبری در اشتراک یافت نشد.');
          }
        } else {
          throw Exception(
            responseData['message'] ?? 'خطا در دریافت لینک‌های اشتراک.',
          );
        }
      } else {
        throw Exception('خطای سرور: ${response.statusCode}');
      }
    } catch (e) {
      // برای خطاهای شبکه یا موارد دیگر
      throw Exception(
        'اتصال به اینترنت وجود ندارد یا سرور در دسترس نیست. VPN خود را خاموش کرده و دوباره تلاش کنید.',
      );
    }
  }

  List<V2RayConfig> _parseShareLinks(List<dynamic> shareLinks) {
    final List<V2RayConfig> configs = [];
    for (var link in shareLinks) {
      try {
        var cleanedLink = link.toString().trim();
        // Sanitize the link to prevent parsing issues with special characters in the path
        try {
          Uri originalUri = Uri.parse(cleanedLink);
          Map<String, String> queryParams = Map.from(
            originalUri.queryParameters,
          );
          if (queryParams.containsKey('path')) {
            queryParams['path'] = queryParams['path']!.replaceAll(
              RegExp(r'[\n\r]'),
              '',
            );
          }
          final cleanedUri = originalUri.replace(queryParameters: queryParams);
          cleanedLink = cleanedUri.toString();
        } catch (e) {
          print(
            'Could not parse link as URI for cleaning: $cleanedLink. Error: $e',
          );
        }

        dynamic parsedResult = FlutterV2ray.parseFromURL(cleanedLink);

        if (parsedResult is V2RayURL) {
          configs.add(V2RayConfig.fromV2RayURL(parsedResult));
        } else {
          print(
            'Error parsing share link: $link. Reason: ${parsedResult.toString()}',
          );
        }
      } catch (e) {
        print('Error parsing share link $link: $e');
      }
    }
    return configs;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('username');
    // ignore: use_build_context_synchronously
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<V2RayConfig>>(
        future: _v2rayConfigFuture,
        builder: (context, snapshot) {
          // ۱. حالت در حال بارگیری
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade400],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'در حال دریافت تنظیمات VPN...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }

          // ۲. حالت خطا
          if (snapshot.hasError) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade800, Colors.red.shade400],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.white, size: 60),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.error.toString().replaceAll("Exception: ", ""),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _retryFetch,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تلاش مجدد'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('خروج'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          // ۳. حالت موفقیت
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            // اگر داده‌ها با موفقیت دریافت شدند، به صفحه اصلی منتقل می‌شویم
            return HomeScreen(configs: snapshot.data!);
          }

          // حالت پیش‌فرض (نباید اتفاق بیفتد)
          return const Center(child: Text('یک خطای ناشناخته رخ داد.'));
        },
      ),
    );
  }
}