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
  late Future<List<V2RayConfig>> _v2rayConfigFuture;
  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

  @override
  void initState() {
    super.initState();
    _v2rayConfigFuture = _fetchV2RayConfig();
  }

  void _retryFetch() {
    setState(() {
      _v2rayConfigFuture = _fetchV2RayConfig();
    });
  }

  Future<List<V2RayConfig>> _fetchV2RayConfig() async {
    try {
      final url = Uri.parse('$_apiBaseUrl?action=getSubscription');
      final response = await http.get(url);
      print('API Response Status: ${response.statusCode}');
      print('API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          final List<dynamic> shareLinks = responseData['share_links'] ?? [];
          print('Received ${shareLinks.length} share links from API.');

          final List<V2RayConfig> allConfigs = [];
          for (var link in shareLinks) {
            String linkString = link.toString().trim();
            if (linkString.startsWith('http://') ||
                linkString.startsWith('https://')) {
              // این یک URL سابسکریپشن است که باید محتوای آن واکشی و رمزگشایی شود
              try {
                final subscriptionConfigs = await _fetchAndParseSubscriptionUrl(
                  linkString,
                );
                allConfigs.addAll(subscriptionConfigs);
              } catch (e) {
                print(
                  'Error fetching or parsing subscription URL $linkString: $e',
                );
              }
            } else {
              // این یک لینک مستقیم V2Ray (vmess, vless, trojan, ss) است
              try {
                final parsedConfig = _parseSingleV2RayLink(linkString);
                if (parsedConfig != null) {
                  allConfigs.add(parsedConfig);
                }
              } catch (e) {
                print('Error parsing direct V2Ray link $linkString: $e');
              }
            }
          }

          if (allConfigs.isNotEmpty) {
            print(
              'Successfully parsed ${allConfigs.length} V2Ray configs in total.',
            );
            return allConfigs;
          } else {
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
      print('Error fetching V2Ray config: $e');
      throw Exception(
        'اتصال به اینترنت وجود ندارد یا سرور در دسترس نیست. VPN خود را خاموش کرده و دوباره تلاش کنید. خطا: $e',
      );
    }
  }

  // تابع جدید برای واکشی و تجزیه محتوای یک URL سابسکریپشن
  Future<List<V2RayConfig>> _fetchAndParseSubscriptionUrl(String url) async {
    print('Fetching content from subscription URL: $url');
    final response = await http.get(Uri.parse(url));

    if (!response.statusCode.toString().startsWith('2')) {
      // Check for 2xx status codes
      throw Exception(
        'Failed to fetch subscription content from $url: ${response.statusCode}',
      );
    }

    // محتوای سابسکریپشن معمولاً Base64 encoded است
    final String base64Content = response.body;
    String decodedContent;
    try {
      decodedContent = utf8.decode(base64.decode(base64Content));
      print('Successfully decoded Base64 content from $url');
    } catch (e) {
      print('Error decoding Base64 content from $url: $e');
      // اگر Base64 نبود، شاید محتوا مستقیماً لینک‌ها باشد
      decodedContent = base64Content;
    }

    final List<V2RayConfig> configs = [];
    final lines = LineSplitter.split(decodedContent); // تقسیم محتوا به خطوط

    for (var line in lines) {
      String trimmedLine = line.trim();
      if (trimmedLine.isNotEmpty) {
        try {
          final parsedConfig = _parseSingleV2RayLink(trimmedLine);
          if (parsedConfig != null) {
            configs.add(parsedConfig);
          }
        } catch (e) {
          print(
            'Error parsing single link from subscription content "$trimmedLine": $e',
          );
        }
      }
    }
    return configs;
  }

  // تابع کمکی برای تجزیه یک لینک V2Ray (vmess, vless, etc.)
  V2RayConfig? _parseSingleV2RayLink(String link) {
    print('Attempting to parse single V2Ray link: $link');
    try {
      // FlutterV2ray.parseFromURL باید لینک‌های پروتکل V2Ray را مستقیماً بپذیرد
      // بدون نیاز به پیش‌پردازش Uri.parse یا URL-decode کردن کامل لینک.
      // اگر لینک حاوی کاراکترهای خاصی در remark باشد، کتابخانه باید آن را مدیریت کند.
      dynamic parsedResult = FlutterV2ray.parseFromURL(link);
      print('Parsed result type for link "$link": ${parsedResult.runtimeType}');

      if (parsedResult is V2RayURL) {
        final v2rayConfig = V2RayConfig.fromV2RayURL(parsedResult);
        print(
          'Successfully added config: ID=${v2rayConfig.id}, Name=${v2rayConfig.name}, Protocol=${v2rayConfig.protocol}, Server=${v2rayConfig.server}, Port=${v2rayConfig.port}',
        );
        return v2rayConfig;
      } else {
        print(
          'Error parsing share link: $link. Reason: Unexpected result type or parsing failed: ${parsedResult.toString()}',
        );
        return null;
      }
    } catch (e) {
      print('Error processing V2Ray link "$link": $e');
      return null;
    }
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

          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return HomeScreen(configs: snapshot.data!);
          }

          return const Center(child: Text('یک خطای ناشناخته رخ داد.'));
        },
      ),
    );
  }
}
