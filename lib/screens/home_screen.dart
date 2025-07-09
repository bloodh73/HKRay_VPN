import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart'; // اضافه کردن این import
import 'package:hkray_vpn/screens/server_list_screen.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import '../services/v2ray_service.dart';
import 'login_screen.dart';
import 'package:shamsi_date/shamsi_date.dart';

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
      final response = await http.get(url);

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final List<dynamic> shareLinks =
              responseData['share_links'] ?? []; // Expecting 'share_links'
          final List<V2RayConfig> updatedConfigs = [];
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
                final cleanedUri = originalUri.replace(
                  queryParameters: queryParams,
                );
                cleanedLink = cleanedUri.toString();
              } catch (e) {
                print(
                  'Could not parse link as URI for cleaning: $cleanedLink. Error: $e',
                );
              }

              dynamic parsedResult = FlutterV2ray.parseFromURL(cleanedLink);

              if (parsedResult is V2RayURL) {
                updatedConfigs.add(V2RayConfig.fromV2RayURL(parsedResult));
              } else {
                String errorMessage =
                    'Unexpected result from parser: ${parsedResult.toString()}';
                print('Error parsing share link $link: $errorMessage');
              }
            } catch (e) {
              print('Error parsing share link $link: $e');
            }
          }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_username),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
                        title: const Text('دستگاه‌های وارد شده'),
                        content: FutureBuilder<int?>(
                          future: currentUserId,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            } else if (snapshot.hasError ||
                                snapshot.data == null) {
                              return const Text('خطا در دریافت شناسه کاربر.');
                            } else {
                              final userId = snapshot.data!;
                              // فراخوانی _fetchLoggedInDevices با userId
                              _fetchLoggedInDevices(userId);
                              return _loggedInDevices.isEmpty
                                  ? const Text('هیچ دستگاهی یافت نشد.')
                                  : SingleChildScrollView(
                                      child: ListBody(
                                        children: _loggedInDevices
                                            .map(
                                              (device) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 4.0,
                                                    ),
                                                child: Text(
                                                  // نمایش نام دستگاه (device_name) و نام کاربری و آخرین ورود
                                                  'دستگاه: ${device['device_name'] ?? 'نامشخص'} (کاربر: ${device['username']}, آخرین ورود: ${device['last_login']})',
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    );
                            }
                          },
                        ),
                        actions: <Widget>[
                          TextButton(
                            child: const Text('بستن'),
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
              // --- پایان بخش جایگزینی ---
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
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Display error message if any
                if (_errorMessage != null)
                  Card(
                    color: Colors.red.shade100,
                    margin: const EdgeInsets.only(bottom: 20),
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
                GestureDetector(
                  onTap: _connectDisconnect,
                  child: Consumer<V2RayService>(
                    builder: (context, v2rayService, child) {
                      _currentStatus =
                          v2rayService.status; // Update local status
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        width: _currentStatus.state == 'CONNECTED' ? 200 : 180,
                        height: _currentStatus.state == 'CONNECTED' ? 200 : 180,
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
                                  // ignore: deprecated_member_use
                                  ? Colors.green.shade300.withOpacity(0.6)
                                  : Colors.blueAccent.shade200.withOpacity(0.6),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.8),
                            width: 4,
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
                              size: 80,
                            ),
                            const SizedBox(height: 10),
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
                                padding: EdgeInsets.only(top: 8.0),
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  strokeWidth: 3,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 30),
                if (widget.configs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 50,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'هیچ سرور معتبری یافت نشد. لطفاً اتصال اینترنت خود را بررسی کنید و دوباره تلاش کنید.',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.orange),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'سرور انتخاب شده: ${_selectedConfig?.remarks ?? 'هیچ سروری انتخاب نشده'}',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _selectServer,
                    icon: const Icon(Icons.list),
                    label: const Text('انتخاب سرور'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                // Enhanced Connection Status Card
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 10,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Consumer<V2RayService>(
                      builder: (context, v2rayService, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'وضعیت اتصال:',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent.shade700,
                                      ),
                                ),
                                Icon(
                                  v2rayService.status.state == 'CONNECTED'
                                      ? Icons.check_circle_outline
                                      : Icons.cancel_outlined,
                                  color:
                                      v2rayService.status.state == 'CONNECTED'
                                      ? Colors.green
                                      : Colors.red,
                                  size: 30,
                                ),
                              ],
                            ),
                            const Divider(height: 20, thickness: 1.5),
                            _buildInfoRow(
                              'وضعیت:',
                              v2rayService.status.state,
                              icon: Icons.info_outline,
                            ),
                            _buildInfoRow(
                              'سرعت دانلود:',
                              '${v2rayService.formatBytes(v2rayService.downloadSpeed)}/s',
                              icon: Icons.arrow_downward,
                            ),
                            _buildInfoRow(
                              'سرعت آپلود:',
                              '${v2rayService.formatBytes(v2rayService.uploadSpeed)}/s',
                              icon: Icons.arrow_upward,
                            ),
                            const Divider(),
                            // _buildInfoRow(
                            //   'پینگ:',
                            //   '${v2rayService.ping} ms',
                            //   icon: Icons.network_check,
                            // ),
                            _buildInfoRow(
                              'دانلود کلی:',
                              v2rayService.formatBytes(
                                v2rayService.totalDownloaded,
                              ),
                              icon: Icons.cloud_download,
                            ),
                            _buildInfoRow(
                              'آپلود کلی:',
                              v2rayService.formatBytes(
                                v2rayService.totalUploaded,
                              ),
                              icon: Icons.cloud_upload,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
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

  Widget _buildInfoRow(String label, String value, {required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueAccent.shade400, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
