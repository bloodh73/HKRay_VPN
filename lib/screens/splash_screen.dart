import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Add this dependency
import '../models/v2ray_config.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'در حال بررسی وضعیت...';
  bool _hasError = false;
  String _errorMessage = '';

  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _statusMessage = 'در حال بررسی اتصال اینترنت...';
        _hasError = false;
      });

      // 1. Check internet connectivity
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        throw Exception('اتصال به اینترنت وجود ندارد.');
      }

      setState(() {
        _statusMessage = 'در حال بررسی وضعیت ورود...';
      });

      // 2. Check login status
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) {
        // Not logged in, navigate to LoginScreen
        // ignore: use_build_context_synchronously
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        return;
      }

      setState(() {
        _statusMessage = 'در حال دریافت تنظیمات VPN...';
      });

      // 3. Fetch V2Ray configurations
      List<V2RayConfig> configs = await _fetchV2RayConfig();

      // If everything is successful, navigate to HomeScreen
      // ignore: use_build_context_synchronously
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeScreen(configs: configs)),
      );
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _statusMessage = 'خطا'; // Change status to reflect error
      });
      print('Initialization error: $e');
    }
  }

  void _retryInitialization() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _statusMessage = 'در حال بررسی وضعیت...';
    });
    _initializeApp();
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
        'خطا در دریافت تنظیمات VPN. لطفاً از اتصال اینترنت خود اطمینان حاصل کرده و دوباره امتحان کنید. خطا: $e',
      );
    }
  }

  Future<List<V2RayConfig>> _fetchAndParseSubscriptionUrl(String url) async {
    print('Fetching content from subscription URL: $url');
    final response = await http.get(Uri.parse(url));

    if (!response.statusCode.toString().startsWith('2')) {
      throw Exception(
        'Failed to fetch subscription content from $url: ${response.statusCode}',
      );
    }

    final String base64Content = response.body;
    String decodedContent;
    try {
      decodedContent = utf8.decode(base64.decode(base64Content));
      print('Successfully decoded Base64 content from $url');
    } catch (e) {
      print('Error decoding Base64 content from $url: $e');
      decodedContent = base64Content;
    }

    final List<V2RayConfig> configs = [];
    final lines = LineSplitter.split(decodedContent);

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

  V2RayConfig? _parseSingleV2RayLink(String link) {
    print('Attempting to parse single V2Ray link: $link');
    try {
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _hasError
                ? [Colors.red.shade800, Colors.red.shade400]
                : [
                    Theme.of(context).primaryColor,
                    Theme.of(context).colorScheme.secondary,
                  ],
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
                if (_hasError)
                  const Icon(Icons.error, color: Colors.white, size: 60)
                else
                  const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  _hasError ? _errorMessage : _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                if (_hasError) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _retryInitialization,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
