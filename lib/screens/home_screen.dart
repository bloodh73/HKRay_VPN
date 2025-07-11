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
import 'dart:io'; // Required for DeviceInfoPlugin
import 'package:device_info_plus/device_info_plus.dart'; // Required for DeviceInfoPlugin

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
        // Pass username instead of userId
        if (_username.isNotEmpty) {
          _fetchLoggedInDevices(_username); // Pass username to the method
        }
      },
    );

    _fetchUserDetails(); // Initial fetch

    // Initial fetch for devices, get username first
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

  // New method to handle initial fetch of logged-in devices with username
  Future<void> _getInitialLoggedInDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username != null && username.isNotEmpty) {
      _fetchLoggedInDevices(username); // Pass username to the method
    } else {
      print(
        'HomeScreen: Username not found for initial logged-in devices fetch.',
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
        _errorMessage = 'کاربر وارد نشده است. لطفا دوباره وارد شوید.';
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
                responseData['message'] ?? 'خطا در واکشی اطلاعات کاربر.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'خطای سرور: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطا در واکشی اطلاعات کاربر: $e';
      });
    }
  }

  // متد جدید برای واکشی لیست دستگاه‌های وارد شده
  // این متد اکنون username را به عنوان پارامتر دریافت می‌کند
  Future<void> _fetchLoggedInDevices(String username) async {
    try {
      // Pass the current user's username to fetchLoggedInDevices
      final devices = await _v2rayService.fetchLoggedInDevices(username);
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
    if (_v2rayService.isConnected) {
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
      return;
    }

    // [MODIFIED] Show a more descriptive loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Text(
                      "در حال دریافت سرورها...",
                      style: TextStyle(fontFamily: 'Vazirmatn'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final url = Uri.parse('$_apiBaseUrl?action=getSubscription');
      final response = await http.get(url);

      if (!mounted) return; // Check if the widget is still in the tree
      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final List<dynamic> shareLinks = responseData['share_links'] ?? [];
          final List<V2RayConfig> updatedConfigs = [];

          for (var link in shareLinks) {
            String linkString = link.toString().trim();
            if (linkString.startsWith('http://') ||
                linkString.startsWith('https://')) {
              try {
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
                  } catch (e) {
                    decodedContent = base64Content;
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
                        }
                      } catch (e) {
                        print('Error parsing sub-link "$trimmedSubLine": $e');
                      }
                    }
                  }
                }
              } catch (e) {
                print('Error fetching subscription URL $linkString: $e');
              }
            } else {
              try {
                dynamic parsedResult = FlutterV2ray.parseFromURL(linkString);
                if (parsedResult is V2RayURL) {
                  updatedConfigs.add(V2RayConfig.fromV2RayURL(parsedResult));
                }
              } catch (e) {
                print('Error parsing direct share link $linkString: $e');
              }
            }
          }

          if (!mounted) return;
          if (updatedConfigs.isNotEmpty) {
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
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                responseData['message'] ?? 'خطا در دریافت لیست سرورها',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Vazirmatn'),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'خطا در اتصال به سرور',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close dialog on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطا: ${e.toString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Vazirmatn'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
                onTap: () async {
                  if (_username.isNotEmpty) {
                    await _fetchLoggedInDevices(_username); // Fetch latest data
                  }
                  _showLoggedInDevicesDialog(); // Show dialog with current data
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
                  if (_username.isNotEmpty) {
                    _fetchLoggedInDevices(
                      _username,
                    ); // Pass username to the method
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
                      width: 150,
                      height: 150,
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
                            size: 50,
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
                              fontSize: 24,
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

              // User Info Card
              // Card(
              //   elevation: 8,
              //   shape: RoundedRectangleBorder(
              //     borderRadius: BorderRadius.circular(25),
              //   ),
              //   margin: const EdgeInsets.only(bottom: 20),
              //   child: Padding(
              //     padding: const EdgeInsets.all(20.0),
              //     child: Column(
              //       children: [
              //         CircleAvatar(
              //           radius: 40,
              //           backgroundColor: Colors.blueAccent.shade100,
              //           child: Icon(
              //             Icons.person,
              //             size: 50,
              //             color: Colors.blueAccent.shade700,
              //           ),
              //         ),
              //         const SizedBox(height: 15),
              //         Text(
              //           _username,
              //           style: TextStyle(
              //             fontSize: 22,
              //             fontWeight: FontWeight.bold,
              //             color: Colors.blueAccent.shade700,
              //           ),
              //         ),
              //         const SizedBox(height: 5),
              //         Text(
              //           _userStatus ?? 'وضعیت نامشخص',
              //           style: TextStyle(
              //             fontSize: 16,
              //             color: Colors.grey.shade700,
              //           ),
              //         ),
              //         const Divider(height: 25, thickness: 1),
              //         _buildInfoRow(
              //           'تاریخ انقضا:',
              //           _expiryDate ?? 'نامشخص',
              //           icon: Icons.calendar_today,
              //           iconColor: Colors.orange.shade700,
              //         ),
              //         _buildInfoRow(
              //           'روزهای باقی مانده:',
              //           '$_remainingDays روز',
              //           icon: Icons.hourglass_empty,
              //           iconColor: Colors.orange.shade700,
              //         ),
              //       ],
              //     ),
              //   ),
              // ),
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

  // New method to encapsulate the dialog logic for logged-in devices
  void _showLoggedInDevicesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Icon(Icons.devices, color: Colors.blueAccent.shade700),
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
          content: _loggedInDevices.isEmpty
              ? const Text(
                  'هیچ دستگاهی یافت نشد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                )
              : SingleChildScrollView(
                  child: ListBody(
                    children: _loggedInDevices.map((device) {
                      final deviceName = device['device_name'] ?? 'نامشخص';
                      final username =
                          device['username'] ??
                          'نامشخص'; // This username is from the device data, not the current user.
                      final lastLoginGregorian =
                          device['last_login'] ?? 'نامشخص';

                      String lastLoginShamsi = 'نامشخص';
                      try {
                        final gregorianDate = DateTime.parse(
                          lastLoginGregorian,
                        );
                        final jalaliDate = Jalali.fromDateTime(gregorianDate);
                        final formatter = jalaliDate.formatter;
                        lastLoginShamsi =
                            '${formatter.yyyy}/${formatter.mm}/${formatter.dd} ${formatter.y}:${formatter.y}:${formatter.y}';
                      } catch (e) {
                        lastLoginShamsi = lastLoginGregorian;
                      }

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _getDeviceIcon(deviceName),
                                color: Colors.blueAccent,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'دستگاه: $deviceName',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'کاربر: $username', // This is the username associated with the device entry
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'آخرین ورود: $lastLoginShamsi',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
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
    final username = prefs.getString('username'); // Get username
    final deviceName = await _getDeviceName(); // Get device name

    // Send logout status to server BEFORE removing user_id from local storage
    if (userId != null && username != null) {
      await _v2rayService.sendLoginStatus(
        userId,
        false,
        deviceName, // Pass deviceName
      );
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

  // Add this method to get device name for logout
  Future<String> _getDeviceName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return "${androidInfo.manufacturer} ${androidInfo.model}";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.name;
    }
    return "Unknown Device";
  }
}
