import 'dart:async';
import 'dart:convert';
import 'package:HKRay_vpn/screens/server_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import '../services/v2ray_service.dart';
import '../services/theme_notifier.dart'; // Import ThemeNotifier
import 'login_screen.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

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
  Timer? _deviceListUpdateTimer;

  String _username = 'کاربر';
  int _totalVolumeMB = 0;
  int _usedVolumeMB = 0;
  int _remainingVolumeMB = 0;
  int _remainingDays = 0;
  String? _expiryDate;
  String? _userStatus;
  List<Map<String, dynamic>> _loggedInDevices = [];
  String? _errorMessage;

  String _currentAppVersion = '1.0.1';

  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

  @override
  void initState() {
    super.initState();
    _v2rayService = Provider.of<V2RayService>(context, listen: false);

    print('HomeScreen - Received ${widget.configs.length} configs');
    widget.configs.asMap().forEach((index, config) {
      print(
        'Config $index: ${config.remarks} - ${config.server}:${config.port}',
      );
    });

    _selectedConfig = _v2rayService.currentConfig ?? widget.configs.firstOrNull;

    _statusSubscription = _v2rayService.statusStream.listen((status) {
      setState(() {
        _currentStatus = status;
      });
    });

    _logSubscription = _v2rayService.logStream.listen((log) {
      print('V2Ray Log: $log');
    });

    _usageUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _fetchUserDetails();
    });

    _deviceListUpdateTimer = Timer.periodic(const Duration(minutes: 5), (
      timer,
    ) async {
      if (_username.isNotEmpty) {
        _fetchLoggedInDevices(_username);
      }
    });

    _fetchUserDetails();
    _getInitialLoggedInDevices();
    _getAppVersion();
  }

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

      Navigator.pop(context);

      if (response.statusCode == 200) {
        final Map<String, dynamic> releaseData = json.decode(response.body);
        final String latestVersion = releaseData['tag_name'] ?? '0.0.0';
        final String? downloadUrl = (releaseData['assets'] as List?)
            ?.firstWhere(
              (asset) => asset['name'].endsWith('.apk'),
              orElse: () => null,
            )?['browser_download_url'];

        final cleanLatestVersion = latestVersion.startsWith('v')
            ? latestVersion.substring(1)
            : latestVersion;
        final cleanCurrentVersion = _currentAppVersion.startsWith('v')
            ? _currentAppVersion.substring(1)
            : _currentAppVersion;

        if (_compareVersions(cleanLatestVersion, cleanCurrentVersion) > 0) {
          _showUpdateDialog(latestVersion, downloadUrl);
        } else {
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
      Navigator.pop(context);
      _showInfoDialog(
        'خطا در بررسی بروزرسانی',
        'خطا در اتصال به سرور GitHub: ${e.toString()}',
      );
    }
  }

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
                  _showInfoDialogWithCopy(
                    'خطا در باز کردن لینک',
                    'امکان باز کردن لینک دانلود به صورت خودکار وجود ندارد. لطفاً لینک زیر را کپی کرده و در مرورگر خود باز کنید:',
                    downloadUrl,
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

  Future<void> _getInitialLoggedInDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username != null && username.isNotEmpty) {
      _fetchLoggedInDevices(username);
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
    _deviceListUpdateTimer?.cancel();
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

            final expiryDateStr = responseData['expiry_date'];
            if (expiryDateStr != null) {
              try {
                final gregorianDate = DateTime.parse(expiryDateStr);
                final jalaliDate = Jalali.fromDateTime(gregorianDate);
                final formatter = jalaliDate.formatter;
                _expiryDate =
                    '${formatter.yyyy}/${formatter.mm}/${formatter.dd}';
              } catch (e) {
                _expiryDate = expiryDateStr;
              }
            }
          });
        } else {
          setState(() {
            _errorMessage =
                responseData['message'] ?? 'اطلاعات کاربر دریافت نشد.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'خطای سرور: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'اطلاعات کاربر دریافت نشد';
      });
    }
  }

  Future<void> _fetchLoggedInDevices(String username) async {
    try {
      final devices = await _v2rayService.fetchLoggedInDevices(username);
      setState(() {
        _loggedInDevices = devices;
      });
    } catch (e) {
      print('Error fetching logged in devices in HomeScreen: $e');
      setState(() {
        _loggedInDevices = [];
      });
    }
  }

  Future<void> _connectDisconnect() async {
    setState(() {
      _errorMessage = null;
    });

    if (_currentStatus.state == 'CONNECTED') {
      await _v2rayService.disconnect();
    } else {
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
        return;
      }

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
        return;
      }

      if (_selectedConfig != null) {
        print(
          'V2Ray Log: Attempting to connect with config address: ${_selectedConfig!.server}',
        );
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
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      );
      return;
    }

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

      if (!mounted) return;
      Navigator.pop(context);

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
        Navigator.pop(context);
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
      return Icons.laptop_windows;
    }
    return Icons.device_unknown;
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isDarkMode = themeNotifier.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _username,
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: isDarkMode ? Color(0xFF1A2B3C) : Color(0xFF3F82CD),
            // gradient: LinearGradient(
            //   colors: [
            //     Theme.of(context).primaryColor,
            //     Theme.of(context).colorScheme.secondary,
            //   ],
            //   begin: Alignment.topLeft,
            //   end: Alignment.bottomRight,
            // ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).appBarTheme.foregroundColor,
            ),
            onPressed: _fetchUserDetails,
            tooltip: 'به‌روزرسانی اطلاعات کاربر',
          ),
        ],
      ),
      drawer: Drawer(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).colorScheme.secondary,
              ],
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
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white70,
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Theme.of(context).primaryColor,
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
              _buildDrawerItem(
                icon: Icons.devices,
                title: 'دستگاه‌های وارد شده',
                onTap: () async {
                  if (_username.isNotEmpty) {
                    await _fetchLoggedInDevices(_username);
                  }
                  _showLoggedInDevicesDialog();
                },
              ),
              _buildDrawerItem(
                icon: Icons.system_update,
                title: 'بروزرسانی برنامه (v$_currentAppVersion)',
                onTap: _checkForUpdate,
              ),
              // Theme Toggle Switch
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isDarkMode ? Icons.light_mode : Icons.dark_mode,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          isDarkMode ? 'حالت روشن' : 'حالت تاریک',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: isDarkMode,
                      onChanged: (value) {
                        themeNotifier.toggleTheme();
                      },
                      activeColor: Colors.white,
                      activeTrackColor: Colors.white.withOpacity(0.5),
                      inactiveThumbColor: Colors.grey.shade700,
                      inactiveTrackColor: Colors.grey.shade500.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white70),
              _buildDrawerItem(
                icon: Icons.refresh,
                title: 'به‌روزرسانی اطلاعات',
                onTap: () async {
                  _fetchUserDetails();
                  if (_username.isNotEmpty) {
                    _fetchLoggedInDevices(_username);
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
            colors: [
              Theme.of(context).colorScheme.background,
              Theme.of(context).colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: _connectDisconnect,
                child: Consumer<V2RayService>(
                  builder: (context, v2rayService, child) {
                    _currentStatus = v2rayService.status;
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
                                  Theme.of(context).primaryColor,
                                  Theme.of(context).colorScheme.secondary,
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _currentStatus.state == 'CONNECTED'
                                ? Colors.green.shade300.withOpacity(0.6)
                                : Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.6),
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
                              fontSize: 18,
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

              if (_errorMessage != null)
                Card(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                  margin: const EdgeInsets.only(bottom: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Updated Server Selection Button with BoxDecoration
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.6),
                      blurRadius: 25,
                      spreadRadius: 8,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                    style: BorderStyle.solid,
                  ),
                ),
                child: ElevatedButton.icon(
                  onPressed: _selectServer,
                  icon: const Icon(Icons.list, size: 24),
                  label: Text(
                    'سرور انتخاب شده: ${_selectedConfig?.remarks ?? 'هیچ سروری انتخاب نشده'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors
                        .transparent, // Make button background transparent
                    foregroundColor: Colors.white, // Text color remains white
                    shadowColor:
                        Colors.transparent, // Remove default button shadow
                    elevation: 0, // Remove default button elevation
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
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
                                  color: Theme.of(context).colorScheme.primary,
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
                            iconColor: Theme.of(context).colorScheme.secondary,
                          ),
                          _buildInfoRow(
                            'سرعت آپلود:',
                            '${v2rayService.formatBytes(v2rayService.uploadSpeed)}/s',
                            icon: Icons.arrow_upward,
                            iconColor: Theme.of(context).colorScheme.secondary,
                          ),
                          const Divider(),
                          _buildInfoRow(
                            'دانلود کلی:',
                            v2rayService.formatBytes(
                              v2rayService.totalDownloaded,
                            ),
                            icon: Icons.cloud_download,
                            iconColor: Theme.of(context).colorScheme.primary,
                          ),
                          _buildInfoRow(
                            'آپلود کلی:',
                            v2rayService.formatBytes(
                              v2rayService.totalUploaded,
                            ),
                            icon: Icons.cloud_upload,
                            iconColor: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

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
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Divider(height: 20, thickness: 1.5),
                      _buildInfoRow(
                        'حجم کلی:',
                        '${(_totalVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.storage,
                        iconColor: Theme.of(context).colorScheme.secondary,
                      ),
                      _buildInfoRow(
                        'حجم مصرفی:',
                        '${(_usedVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.pie_chart,
                        iconColor: Theme.of(context).colorScheme.error,
                      ),
                      _buildInfoRow(
                        'حجم باقی مانده:',
                        '${(_remainingVolumeMB / 1024).toStringAsFixed(2)} GB',
                        icon: Icons.cloud_queue,
                        iconColor: Theme.of(context).colorScheme.secondary,
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

  void _showLoggedInDevicesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Theme.of(context).cardTheme.color,
          title: Row(
            children: [
              Icon(Icons.devices, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'دستگاه‌های وارد شده',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: _loggedInDevices.isEmpty
              ? Text(
                  'هیچ دستگاهی یافت نشد.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color, // Ensure text color is theme-aware
                  ),
                )
              : SingleChildScrollView(
                  child: ListBody(
                    children: _loggedInDevices.map((device) {
                      final deviceName = device['device_name'] ?? 'نامشخص';
                      final username = device['username'] ?? 'نامشخص';
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
                            '${formatter.yyyy}/${formatter.mm}/${formatter.dd} ${formatter.tHH}:${formatter.tMM}:${formatter.tMS}';
                      } catch (e) {
                        lastLoginShamsi = lastLoginGregorian;
                      }

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _getDeviceIcon(deviceName),
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'دستگاه: $deviceName',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'کاربر: $username',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'آخرین ورود: $lastLoginShamsi',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                    Text(
                                      device['is_logged_in'] == true
                                          ? 'وضعیت: آنلاین'
                                          : 'وضعیت: آفلاین',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: device['is_logged_in'] == true
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
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
                foregroundColor: Theme.of(context).colorScheme.primary,
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
                color: iconColor ?? Theme.of(context).colorScheme.secondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final username = prefs.getString('username');
    final deviceName = await _getDeviceName();

    if (userId != null && username != null) {
      await _v2rayService.sendLoginStatus(userId, false, deviceName);
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
