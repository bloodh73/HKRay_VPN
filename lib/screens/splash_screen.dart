import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/v2ray_config.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'package:package_info_plus/package_info_plus.dart'; // Import for package info
import 'package:url_launcher/url_launcher.dart'; // Import for launching URLs
import 'package:flutter/services.dart'; // For Clipboard

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusMessage = 'در حال بررسی وضعیت...';
  bool _hasError = false;
  String _errorMessage = '';
  String _currentAppVersion = '1.0.1'; // Default version, will be updated

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

      // 3. Get current app version (needed for update check)
      await _getAppVersion();

      // 4. Check for app updates
      setState(() {
        _statusMessage = 'در حال بررسی بروزرسانی برنامه...';
      });
      await _checkForUpdate(); // This will show dialogs and potentially halt/redirect

      // If the update check completes and doesn't redirect (e.g., user clicked "Later"), proceed.
      setState(() {
        _statusMessage = 'در حال دریافت تنظیمات VPN...';
      });

      // 5. Fetch V2Ray configurations
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
        _statusMessage = 'خطا';
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

  // --- App Update Logic (Copied from home_screen.dart) ---
  Future<void> _getAppVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _currentAppVersion = packageInfo.version;
      });
    } catch (e) {
      print('Error getting app version: $e');
      setState(() {
        _currentAppVersion = 'نامشخص';
      });
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final String githubApiUrl =
          'https://api.github.com/repos/bloodh73/HKRay_VPN/releases/latest';
      final response = await http.get(Uri.parse(githubApiUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> releaseData = json.decode(response.body);
        final String latestVersion = releaseData['tag_name'] ?? '0.0.0';
        final String? downloadUrl = (releaseData['assets'] as List?)
            ?.firstWhere(
              (asset) => asset['name'].endsWith('.apk'),
              orElse: () => null,
            )?['browser_download_url'];

        // Remove 'v' prefix if exists for comparison
        final cleanLatestVersion = latestVersion.startsWith('v')
            ? latestVersion.substring(1)
            : latestVersion;
        final cleanCurrentVersion = _currentAppVersion.startsWith('v')
            ? _currentAppVersion.substring(1)
            : _currentAppVersion;

        if (_compareVersions(cleanLatestVersion, cleanCurrentVersion) > 0) {
          // New version available
          // ignore: use_build_context_synchronously
          await _showUpdateDialog(latestVersion, downloadUrl);
        }
        // If no new version, or user dismisses, continue _initializeApp
      } else {
        print('Error checking for update: ${response.statusCode}');
        // Optionally show a non-blocking message or log the error
      }
    } catch (e) {
      print('Error checking for update (network/parsing): $e');
      // Optionally show a non-blocking message or log the error
    }
  }

  // Helper to compare version strings (e.g., "1.2.3" vs "1.2.4")
  int _compareVersions(String v1, String v2) {
    final List<int> v1Parts = v1.split('.').map(int.parse).toList();
    final List<int> v2Parts = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < v1Parts.length && i < v2Parts.length; i++) {
      if (v1Parts[i] > v2Parts[i]) return 1;
      if (v1Parts[i] < v2Parts[i]) return -1;
    }
    return v1Parts.length.compareTo(v2Parts.length);
  }

  Future<void> _showUpdateDialog(
    String latestVersion,
    String? downloadUrl,
  ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap a button
      builder: (ctx) => AlertDialog(
        title: const Text(
          'بروزرسانی جدید موجود است!',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'نسخه جدید $latestVersion در دسترس است. آیا مایل به بروزرسانی هستید؟',
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('بعدا'),
            onPressed: () {
              Navigator.of(ctx).pop(); // Dismiss dialog, continue app flow
            },
          ),
          ElevatedButton(
            child: const Text('بروزرسانی'),
            onPressed: () async {
              Navigator.of(ctx).pop(); // Dismiss dialog
              if (downloadUrl != null) {
                print('Attempting to launch URL: $downloadUrl');
                bool launched = false;
                try {
                  launched = await launchUrl(
                    Uri.parse(downloadUrl),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {
                  print('Error launching URL: $e');
                  launched = false;
                }

                if (!launched) {
                  // ignore: use_build_context_synchronously
                  _showInfoDialogWithCopy(
                    'خطا در باز کردن لینک',
                    'امکان باز کردن لینک دانلود به صورت خودکار وجود ندارد. لطفاً لینک زیر را کپی کرده و در مرورگر خود باز کنید:',
                    downloadUrl,
                  );
                }
              } else {
                // ignore: use_build_context_synchronously
                _showInfoDialog('خطا', 'لینک دانلود فایل بروزرسانی یافت نشد.');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: const Text('باشه'),
            onPressed: () {
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _showInfoDialogWithCopy(String title, String message, String copyText) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: copyText));
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('لینک کپی شد!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                copyText,
                style: const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('کپی لینک'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyText));
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('لینک کپی شد!'),
                  duration: Duration(seconds: 2),
                ),
              );
              // ignore: use_build_context_synchronously
              Navigator.of(ctx).pop();
            },
          ),
          TextButton(
            child: const Text('بستن'),
            onPressed: () {
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
  // --- End App Update Logic ---

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
        'خطا در دریافت تنظیمات VPN. لطفاً از اتصال اینترنت خود اطمینان حاصل کرده و دوباره امتحان کنید. خطا',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _hasError
                ? [
                    Theme.of(context).colorScheme.error,
                    Theme.of(context).colorScheme.error.withOpacity(0.8),
                  ]
                : [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColorDark,
                  ],
          ),
        ),
        child: Center(
          child: _hasError ? _buildErrorWidget() : _buildLoadingWidget(),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      margin: const EdgeInsets.all(24.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 64),
          const SizedBox(height: 20),
          const Text(
            'خطا در اتصال به سرور',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.red),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _retryInitialization,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30.0),
              ),
            ),
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('تلاش مجدد', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      margin: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Logo with animation
          Container(
            width: 120,
            height: 120,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Status Message
          Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          // Animated Progress Bar
          Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(seconds: 2),
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(0.8),
                  ),
                  minHeight: 6,
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // App Version
          Text(
            'نسخه $_currentAppVersion',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
