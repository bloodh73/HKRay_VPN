import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:hkray_vpn/screens/server_list_screen.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import '../services/v2ray_service.dart';
import 'login_screen.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:package_info_plus/package_info_plus.dart'; // Import for package info
import 'package:url_launcher/url_launcher.dart'; // Import for launching URLs

class HomeScreen extends StatefulWidget {
  final List<V2RayConfig> configs;

  const HomeScreen({Key? key, required this.configs}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final V2RayService _v2rayService;
  V2RayConfig? _selectedConfig;
  V2RayStatus _currentStatus = V2RayStatus(state: 'IDLE');
  StreamSubscription<V2RayStatus>? _statusSubscription;
  StreamSubscription<String>? _logSubscription;
  Timer? _usageUpdateTimer;
  Timer? _deviceListUpdateTimer; // تایمر جدید برای به‌روزرسانی لیست دستگاه‌ها

  // User data
  String _username = 'کاربر';
  int _totalVolumeMB = 0;
  int _usedVolumeMB = 0;
  int _remainingVolumeMB = 0;
  int _remainingDays = 0;
  String? _expiryDate;
  String? _userStatus;
  List<Map<String, dynamic>> _loggedInDevices =
      []; // لیست جدید برای نگهداری دستگاه‌های وارد شده
  // ignore: unused_field
  String? _errorMessage; // For displaying API fetch errors

  String _currentAppVersion = '1.0.1'; // Default version, will be updated

  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

  @override
  void initState() {
    super.initState();
    _v2rayService = Provider.of<V2RayService>(context, listen: false);

    // Debug print to check received configs
    print('HomeScreen - Received ${widget.configs.length} configs');
    widget.configs.asMap().forEach((index, config) {
      print(
        'Config $index: ${config.remarks} - ${config.server}:${config.port}',
      );
    });

    // Initialize _selectedConfig from V2RayService's currentConfig or the first available config
    _selectedConfig = _v2rayService.currentConfig ?? widget.configs.firstOrNull;

    _statusSubscription = _v2rayService.statusStream.listen((status) {
      setState(() {
        _currentStatus = status;
      });
    });

    _logSubscription = _v2rayService.logStream.listen((log) {
      // You can display logs in a UI component if needed, or just keep them for debugging
      print('V2Ray Log: $log');
    });

    // Start a timer to fetch user details periodically
    _usageUpdateTimer = Timer.periodic(
      const Duration(minutes: 1), // Fetch every minute
      (timer) {
        _fetchUserDetails();
      },
    );

    // شروع تایمر برای واکشی لیست دستگاه‌ها
    _deviceListUpdateTimer = Timer.periodic(
      const Duration(minutes: 5), // هر 5 دقیقه لیست دستگاه‌ها را به‌روز کن
      (timer) async {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getInt('user_id');
        if (userId != null) {
          _fetchLoggedInDevices(userId); // Pass userId to the method
        }
      },
    );

    _fetchUserDetails(); // Initial fetch

    // Initial fetch for devices, get userId first
    _getInitialLoggedInDevices();

    // Get current app version
    _getAppVersion();
  }

  // New method to get the current app version
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

  // New method to check for updates on GitHub
  Future<void> _checkForUpdate() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      final String githubApiUrl =
          'https://api.github.com/repos/bloodh73/HKRay_VPN/releases/latest';
      final response = await http.get(Uri.parse(githubApiUrl));

      Navigator.pop(context); // Close loading dialog

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
          _showUpdateDialog(latestVersion, downloadUrl);
        } else {
          // No new version
          _showInfoDialog(
            'بروزرسانی',
            'شما از آخرین نسخه برنامه استفاده می‌کنید. (نسخه $_currentAppVersion)',
          );
        }
      } else {
        _showInfoDialog(
          'خطا در بررسی بروزرسانی',
          'امکان بررسی بروزرسانی وجود ندارد. کد خطا: ${response.statusCode}',
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog in case of error
      _showInfoDialog(
        'خطا در بررسی بروزرسانی',
        'خطا در اتصال به سرور GitHub: ${e.toString()}',
      );
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

  void _showUpdateDialog(String latestVersion, String? downloadUrl) {
    showDialog(
      context: context,
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
              Navigator.of(ctx).pop();
            },
          ),
          ElevatedButton(
            child: const Text('بروزرسانی'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (downloadUrl != null) {
                if (await canLaunchUrl(Uri.parse(downloadUrl))) {
                  await launchUrl(Uri.parse(downloadUrl));
                } else {
                  _showInfoDialog(
                    'خطا',
                    'امکان باز کردن لینک دانلود وجود ندارد.',
                  );
                }
              } else {
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

  // New method to handle initial fetch of logged-in devices with userId
  Future<void> _getInitialLoggedInDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId != null) {
      _fetchLoggedInDevices(userId); // Pass userId to the method
    } else {
      print(
        'HomeScreen: User ID not found for initial logged-in devices fetch.',
      );
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _logSubscription?.cancel();
    _usageUpdateTimer?.cancel();
    _deviceListUpdateTimer?.cancel(); // کنسل کردن تایمر دستگاه‌ها
    super.dispose();
  }

  Future<void> _fetchUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final username = prefs.getString('username');

    if (userId == null) {
      setState(() {
        _errorMessage = 'User not logged in. Please log in again.';
      });
      return;
    }

    setState(() {
      _username = username ?? 'کاربر';
      _errorMessage = null;
    });

    final url = Uri.parse('$_apiBaseUrl?action=getUserDetails&user_id=$userId');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            _totalVolumeMB = responseData['total_volume'] ?? 0;
            _usedVolumeMB = responseData['used_volume'] ?? 0;
            _remainingVolumeMB = responseData['remaining_volume'] ?? 0;
            _remainingDays = responseData['remaining_days'] ?? 0;
            _userStatus = responseData['status'];

            // --- شروع بخش تبدیل تاریخ ---
            final expiryDateStr = responseData['expiry_date'];
            if (expiryDateStr != null) {
              try {
                final gregorianDate = DateTime.parse(expiryDateStr);
                final jalaliDate = Jalali.fromDateTime(gregorianDate);
                final formatter = jalaliDate.formatter;
                // فرمت تاریخ به صورت: 1404/05/10
                _expiryDate =
                    '${formatter.yyyy}/${formatter.mm}/${formatter.dd}';
              } catch (e) {
                _expiryDate =
                    expiryDateStr; // اگر تبدیل ناموفق بود، همان تاریخ میلادی نمایش داده شود
              }
            }
            // --- پایان بخش تبدیل تاریخ ---
          });
        } else {
          setState(() {
            _errorMessage =
                responseData['message'] ?? 'Failed to fetch user info.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Server error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching user details: $e';
      });
    }
  }

  // متد جدید برای واکشی لیست دستگاه‌های وارد شده
  // این متد اکنون userId را به عنوان پارامتر دریافت می‌کند
  Future<void> _fetchLoggedInDevices(int userId) async {
    try {
      // Pass the current user's ID to fetchLoggedInDevices
      final devices = await _v2rayService.fetchLoggedInDevices(userId);
      setState(() {
        _loggedInDevices = devices;
      });
    } catch (e) {
      print('Error fetching logged in devices in HomeScreen: $e');
      setState(() {
        _loggedInDevices = []; // در صورت خطا، لیست را خالی کن
      });
    }
  }

  Future<void> _connectDisconnect() async {
    // پاک کردن پیام‌های خطای قبلی
    setState(() {
      _errorMessage = null;
    });

    if (_currentStatus.state == 'CONNECTED') {
      // اگر وضعیت فعلی "متصل" است، آن را قطع کن
      await _v2rayService.disconnect();
    } else {
      // --- شروع بخش اضافه شده ---
      // اگر کاربر در حال تلاش برای اتصال است، اعتبار حساب او را بررسی کن

      // ۱. بررسی روزهای باقیمانده
      if (_remainingDays <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'اشتراک شما منقضی شده است. لطفاً آن را تمدید کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        );
        return; // از اتصال جلوگیری کن
      }

      // ۲. بررسی حجم باقیمانده (بر اساس مگابایت)
      if (_remainingVolumeMB <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حجم اینترنت شما به پایان رسیده است.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        );
        return; // از اتصال جلوگیری کن
      }
      // --- پایان بخش اضافه شده ---

      // اگر اعتبار حساب معتبر بود، فرآیند اتصال را ادامه بده
      if (_selectedConfig != null) {
        print(
          'V2Ray Log: Attempting to connect with config address: ${_selectedConfig!.server}',
        );
        // ارسال V2RayConfig object به جای fullConfigJson
        final success = await _v2rayService.connect(_selectedConfig!);
        if (!success) {
          setState(() {
            _errorMessage = 'اتصال به V2Ray ناموفق بود. لطفا دوباره تلاش کنید.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'لطفا یک سرور را انتخاب کنید.';
        });
      }
    }
  }

  Future<void> _selectServer() async {
    print('HomeScreen: _selectServer method called.'); // لاگ جدید
    // Check connection status first
    if (_v2rayService.isConnected) {
      // If connected, show a SnackBar and exit the method
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'برای تغییر سرور، ابتدا اتصال را قطع کنید',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Vazirmatn'),
          ),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      );
      return; // Prevent further code execution
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      // Fetch the latest server list from API
      final url = Uri.parse(
        '$_apiBaseUrl?action=getSubscription',
      ); // Changed action to getSubscription
      print('HomeScreen: Fetching server list from API: $url'); // لاگ جدید
      final response = await http.get(url);

      Navigator.pop(context); // Close loading dialog

      print(
        'HomeScreen: API response status for server list: ${response.statusCode}',
      ); // لاگ جدید
      print(
        'HomeScreen: API response body for server list: ${response.body}',
      ); // لاگ جدید

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final List<dynamic> shareLinks =
              responseData['share_links'] ?? []; // Expecting 'share_links'
          print(
            'HomeScreen: Received ${shareLinks.length} share links for server list.',
          ); // لاگ جدید
          final List<V2RayConfig> updatedConfigs = [];

          // Re-use the parsing logic from VpnWrapperScreen
          for (var link in shareLinks) {
            String linkString = link.toString().trim();
            if (linkString.startsWith('http://') ||
                linkString.startsWith('https://')) {
              try {
                // Assuming _fetchAndParseSubscriptionUrl is accessible or re-implement here
                // For simplicity, let's re-implement the logic needed for subscription URLs here
                // Or, better, refactor VpnWrapperScreen's parsing logic into V2RayService
                // For now, I'll put a placeholder and suggest refactoring.
                print(
                  'HomeScreen: Encountered subscription URL in _selectServer: $linkString. This needs proper handling.',
                );
                // Placeholder: In a real app, you'd call a shared parsing method here.
                // For this example, we'll just try to parse it as a direct link, which might fail.
                final subscriptionResponse = await http.get(
                  Uri.parse(linkString),
                );
                if (subscriptionResponse.statusCode.toString().startsWith(
                  '2',
                )) {
                  final String base64Content = subscriptionResponse.body;
                  String decodedContent;
                  try {
                    decodedContent = utf8.decode(base64.decode(base64Content));
                    print(
                      'HomeScreen: Successfully decoded Base64 content from subscription URL.',
                    );
                  } catch (e) {
                    print(
                      'HomeScreen: Error decoding Base64 content from subscription URL: $e',
                    );
                    decodedContent = base64Content; // Fallback if not Base64
                  }
                  final lines = LineSplitter.split(decodedContent);
                  for (var subLine in lines) {
                    String trimmedSubLine = subLine.trim();
                    if (trimmedSubLine.isNotEmpty) {
                      try {
                        dynamic parsedSubResult = FlutterV2ray.parseFromURL(
                          trimmedSubLine,
                        );
                        if (parsedSubResult is V2RayURL) {
                          updatedConfigs.add(
                            V2RayConfig.fromV2RayURL(parsedSubResult),
                          );
                          print(
                            'HomeScreen: Added config from subscription: ${parsedSubResult.remark}',
                          );
                        } else {
                          print(
                            'HomeScreen: Failed to parse sub-link "$trimmedSubLine": ${parsedSubResult.toString()}',
                          );
                        }
                      } catch (e) {
                        print(
                          'HomeScreen: Error parsing sub-link "$trimmedSubLine": $e',
                        );
                      }
                    }
                  }
                } else {
                  print(
                    'HomeScreen: Failed to fetch subscription content from $linkString: ${subscriptionResponse.statusCode}',
                  );
                }
              } catch (e) {
                print(
                  'HomeScreen: Error fetching or parsing subscription URL $linkString: $e',
                );
              }
            } else {
              // Direct V2Ray link
              try {
                dynamic parsedResult = FlutterV2ray.parseFromURL(linkString);

                if (parsedResult is V2RayURL) {
                  updatedConfigs.add(V2RayConfig.fromV2RayURL(parsedResult));
                  print(
                    'HomeScreen: Added direct config: ${parsedResult.remark}',
                  ); // لاگ جدید
                } else {
                  String errorMessage =
                      'Unexpected result from parser for link "$linkString": ${parsedResult.toString()}';
                  print(
                    'HomeScreen: Error parsing share link: $errorMessage',
                  ); // لاگ جدید
                }
              } catch (e) {
                print(
                  'HomeScreen: Error parsing direct share link $linkString: $e',
                ); // لاگ جدید
              }
            }
          }

          print(
            'HomeScreen: Total updatedConfigs count: ${updatedConfigs.length}',
          ); // لاگ جدید

          if (updatedConfigs.isNotEmpty) {
            // Show server list with updated configs
            final selected = await Navigator.push<V2RayConfig?>(
              context,
              MaterialPageRoute(
                builder: (context) => ServerListScreen(
                  configs: updatedConfigs,
                  currentSelectedConfig: _selectedConfig,
                ),
              ),
            );

            if (selected != null && selected != _selectedConfig) {
              setState(() {
                _selectedConfig = selected;
              });

              // Update the widget's configs for future use
              widget.configs.clear();
              widget.configs.addAll(updatedConfigs);
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'هیچ سرور معتبری یافت نشد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Vazirmatn'),
                ),
                backgroundColor: Colors.orangeAccent,
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
            );
          }
        } else {
          // Show error if server list couldn't be fetched
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['message'] ?? 'خطا در دریافت لیست سرورها',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Vazirmatn'),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(12),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          );
        }
      } else {
        // Show network error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'خطا در اتصال به سرور',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog in case of error
      print('HomeScreen: Error in _selectServer: $e'); // لاگ جدید
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'خطا در دریافت اطلاعات سرورها: ${e.toString()}', // Display the actual error
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Vazirmatn'),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      );
    }
  }

  // Helper to get device icon based on device name
  IconData _getDeviceIcon(String deviceName) {
    deviceName = deviceName.toLowerCase();
    if (deviceName.contains('android')) {
      return Icons.android;
    } else if (deviceName.contains('ios') ||
        deviceName.contains('iphone') ||
        deviceName.contains('ipad')) {
      return Icons.phone_iphone;
    } else if (deviceName.contains('windows')) {
      return Icons.desktop_windows;
    } else if (deviceName.contains('mac') || deviceName.contains('macos')) {
      return Icons.laptop_mac;
    } else if (deviceName.contains('linux')) {
      return Icons.laptop_windows; // Generic laptop icon for Linux
    }
    return Icons.device_unknown; // Default icon
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '❤️ $_username',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent.shade700, Colors.blueAccent.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchUserDetails,
            tooltip: 'به‌روزرسانی اطلاعات کاربر',
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent.shade700, Colors.blueAccent.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.transparent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white70,
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _userStatus ?? 'وضعیت نامشخص',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDrawerItem(
                icon: Icons.data_usage,
                // تقسیم بر 1024 برای تبدیل به GB و نمایش با دو رقم اعشار
                title:
                    'حجم کلی: ${(_totalVolumeMB / 1024).toStringAsFixed(2)} GB',
              ),
              _buildDrawerItem(
                icon: Icons.cloud_upload,
                title:
                    'حجم مصرفی: ${(_usedVolumeMB / 1024).toStringAsFixed(2)} GB',
              ),
              _buildDrawerItem(
                icon: Icons.cloud_download,
                title:
                    'باقی مانده: ${(_remainingVolumeMB / 1024).toStringAsFixed(2)} GB',
              ),
              const Divider(color: Colors.white70),
              _buildDrawerItem(
                icon: Icons.calendar_today,
                title: 'روزهای باقی مانده: $_remainingDays',
              ),
              _buildDrawerItem(
                icon: Icons.date_range,
                title: 'تاریخ انقضا: $_expiryDate',
              ),
              const Divider(color: Colors.white70),
              // بخش جدید برای نمایش دستگاه‌های وارد شده
              _buildDrawerItem(
                icon: Icons.devices,
                title: 'دستگاه‌های وارد شده',
                onTap: () {
                  // مطمئن می‌شویم که userId موجود است قبل از فراخوانی
                  final currentUserId = SharedPreferences.getInstance().then((
                    prefs,
                  ) {
                    return prefs.getInt('user_id');
                  });

                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        // Enhanced AlertDialog styling
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        backgroundColor: Colors.white,
                        title: Row(
                          children: [
                            Icon(
                              Icons.devices,
                              color: Colors.blueAccent.shade700,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'دستگاه‌های وارد شده',
                              style: TextStyle(
                                color: Colors.blueAccent.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        content: FutureBuilder<int?>(
                          future: currentUserId,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                height: 100, // Give some height for loading
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            } else if (snapshot.hasError ||
                                snapshot.data == null) {
                              return const Text(
                                'خطا در دریافت شناسه کاربر.',
                                style: TextStyle(color: Colors.red),
                              );
                            } else {
                              final userId = snapshot.data!;
                              // فراخوانی _fetchLoggedInDevices با userId
                              _fetchLoggedInDevices(userId);
                              return _loggedInDevices.isEmpty
                                  ? const Text(
                                      'هیچ دستگاهی یافت نشد.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    )
                                  : SingleChildScrollView(
                                      child: ListBody(
                                        children: _loggedInDevices.map((
                                          device,
                                        ) {
                                          final deviceName =
                                              device['device_name'] ?? 'نامشخص';
                                          final username =
                                              device['username'] ?? 'نامشخص';
                                          final lastLoginGregorian =
                                              device['last_login'] ?? 'نامشخص';

                                          String lastLoginShamsi = 'نامشخص';
                                          try {
                                            final gregorianDate =
                                                DateTime.parse(
                                                  lastLoginGregorian,
                                                );
                                            final jalaliDate =
                                                Jalali.fromDateTime(
                                                  gregorianDate,
                                                );
                                            final formatter =
                                                jalaliDate.formatter;
                                            lastLoginShamsi =
                                                '${formatter.yyyy}/${formatter.mm}/${formatter.dd} ${formatter.yy}:${formatter.yy}:${formatter.yy}';
                                          } catch (e) {
                                            // Fallback if parsing fails
                                            lastLoginShamsi =
                                                lastLoginGregorian;
                                          }

                                          return Card(
                                            elevation: 2,
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 6.0,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                12.0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    _getDeviceIcon(deviceName),
                                                    color: Colors.blueAccent,
                                                    size: 28,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'دستگاه: $deviceName',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          'کاربر: $username',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          'آخرین ورود: $lastLoginShamsi', // Display Shamsi date
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color: Colors
                                                                    .black45,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    );
                            }
                          },
                        ),
                        actions: <Widget>[
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blueAccent.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'بستن',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              _buildDrawerItem(
                icon: Icons.system_update,
                title: 'بروزرسانی برنامه (v$_currentAppVersion)',
                onTap: _checkForUpdate,
              ),
              const Divider(color: Colors.white70),
              _buildDrawerItem(
                icon: Icons.refresh,
                title: 'به‌روزرسانی اطلاعات',
                onTap: () async {
                  _fetchUserDetails();
                  final prefs = await SharedPreferences.getInstance();
                  final userId = prefs.getInt('user_id');
                  if (userId != null) {
                    _fetchLoggedInDevices(userId); // Pass userId to the method
                  }
                },
              ),
              _buildDrawerItem(
                icon: Icons.logout,
                title: 'خروج',
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main Connect/Disconnect Button
              GestureDetector(
                onTap: _connectDisconnect,
                child: Consumer<V2RayService>(
                  builder: (context, v2rayService, child) {
                    _currentStatus = v2rayService.status; // Update local status
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      width: 220,
                      height: 220,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _currentStatus.state == 'CONNECTED'
                              ? [Colors.green.shade600, Colors.green.shade400]
                              : [
                                  Colors.blueAccent.shade700,
                                  Colors.blueAccent.shade400,
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _currentStatus.state == 'CONNECTED'
                                ? Colors.green.shade300.withOpacity(0.6)
                                : Colors.blueAccent.shade200.withOpacity(0.6),
                            blurRadius: 25,
                            spreadRadius: 8,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withOpacity(0.8),
                          width: 5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentStatus.state == 'CONNECTED'
                                ? Icons.vpn_key
                                : Icons.vpn_key_off,
                            color: Colors.white,
                            size: 90,
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _currentStatus.state == 'CONNECTED'
                                ? 'متصل'
                                : _currentStatus.state == 'CONNECTING'
                                ? 'در حال اتصال...'
                                : 'قطع',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_currentStatus.state == 'CONNECTING')
                            const Padding(
                              padding: EdgeInsets.only(top: 10.0),
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                                strokeWidth: 4,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Error Message Card (if any)
              if (_errorMessage != null)
                Card(
                  color: Colors.red.shade100,
                  margin: const EdgeInsets.only(bottom: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // const SizedBox(height: 20),

              // Server Selection Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selectServer,
                  icon: const Icon(Icons.list, size: 24),
                  label: Text(
                    'سرور انتخاب شده: ${_selectedConfig?.remarks ?? 'هیچ سروری انتخاب نشده'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    elevation: 5,
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Connection Speed Card
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Consumer<V2RayService>(
                    builder: (context, v2rayService, child) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'وضعیت اتصال:',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent.shade700,
                                ),
                          ),
                          const Divider(height: 20, thickness: 1.5),
                          _buildInfoRow(
                            'وضعیت:',
                            v2rayService.status.state,
                            icon: Icons.info_outline,
                            iconColor: v2rayService.status.state == 'CONNECTED'
                                ? Colors.green
                                : Colors.red,
                          ),
                          _buildInfoRow(
                            'سرعت دانلود:',
                            '${v2rayService.formatBytes(v2rayService.downloadSpeed)}/s',
                            icon: Icons.arrow_downward,
                            iconColor: Colors.blue.shade400,
                          ),
                          _buildInfoRow(
                            'سرعت آپلود:',
                            '${v2rayService.formatBytes(v2rayService.uploadSpeed)}/s',
                            icon: Icons.arrow_upward,
                            iconColor: Colors.orange.shade400,
                          ),
                          const Divider(),
                          _buildInfoRow(
                            'دانلود کلی:',
                            v2rayService.formatBytes(
                              v2rayService.totalDownloaded,
                            ),
                            icon: Icons.cloud_download,
                            iconColor: Colors.teal.shade400,
                          ),
                          _buildInfoRow(
                            'آپلود کلی:',
                            v2rayService.formatBytes(
                              v2rayService.totalUploaded,
                            ),
                            icon: Icons.cloud_upload,
                            iconColor: Colors.brown.shade400,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Usage Statistics Card
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'آمار مصرف:',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent.shade700,
                        ),
                      ),
                      const Divider(height: 20, thickness: 1.5),
                      _buildInfoRow(
                        'حجم کلی:',
                        '${(_totalVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.storage,
                        iconColor: Colors.purple.shade400,
                      ),
                      _buildInfoRow(
                        'حجم مصرفی:',
                        '${(_usedVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.pie_chart,
                        iconColor: Colors.red.shade400,
                      ),
                      _buildInfoRow(
                        'حجم باقی مانده:',
                        '${(_remainingVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.cloud_queue,
                        iconColor: Colors.green.shade400,
                      ),
                    ],
                  ),
                ),
              ),

              // Logout Button
              // SizedBox(
              //   width: double.infinity,
              //   child: ElevatedButton.icon(
              //     onPressed: _logout,
              //     icon: const Icon(Icons.logout, size: 24),
              //     label: const Text(
              //       'خروج از حساب',
              //       style: TextStyle(fontSize: 18),
              //     ),
              //     style: ElevatedButton.styleFrom(
              //       padding: const EdgeInsets.symmetric(vertical: 15),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(15),
              //       ),
              //       backgroundColor: Colors.redAccent,
              //       foregroundColor: Colors.white,
              //       elevation: 5,
              //     ),
              //   ),
              // ),
              // User Info Card
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.blueAccent.shade100,
                        child: Icon(
                          Icons.person,
                          size: 50,
                          color: Colors.blueAccent.shade700,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        _username,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent.shade700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _userStatus ?? 'وضعیت نامشخص',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Divider(height: 25, thickness: 1),
                      _buildInfoRow(
                        'تاریخ انقضا:',
                        _expiryDate ?? 'نامشخص',
                        icon: Icons.calendar_today,
                        iconColor: Colors.orange.shade700,
                      ),
                      _buildInfoRow(
                        'روزهای باقی مانده:',
                        '$_remainingDays روز',
                        icon: Icons.hourglass_empty,
                        iconColor: Colors.orange.shade700,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    required IconData icon,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: iconColor ?? Colors.blueAccent.shade400,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id'); // Get userId before removing it

    // Send logout status to server BEFORE removing user_id from local storage
    if (userId != null) {
      // When logging out, we don't send deviceName as it's not relevant for logout status
      await _v2rayService.sendLoginStatus(
        userId,
        false,
        '',
      ); // Pass empty string for deviceName
    }

    await prefs.remove('user_id');
    await prefs.remove('username');
    if (_currentStatus.state == 'CONNECTED') {
      await _v2rayService.disconnect();
    }
    Navigator.pushReplacement(
      // ignore: use_build_context_synchronously
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }
}
