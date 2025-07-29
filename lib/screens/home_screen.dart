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
import 'package:loading_indicator/loading_indicator.dart'; // Import the loading_indicator package

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

  DateTime? _connectionTime;



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

    // Load selected server from SharedPreferences
    SharedPreferences.getInstance().then((prefs) async {
      final savedId = prefs.getString('selected_server_id');
      
      if (savedId != null) {
        try {
          final selectedConfig = widget.configs.firstWhere(
            (config) => config.id == savedId,
          );
          setState(() {
            _selectedConfig = selectedConfig;
          });
          await _v2rayService.connect(selectedConfig);
        } catch (e) {
          print('Error finding saved server: $e');
          final firstConfig = widget.configs.firstOrNull;
          setState(() {
            _selectedConfig = firstConfig;
          });
          if (firstConfig != null) {
            await _v2rayService.connect(firstConfig);
          }
        }
      } else {
        final firstConfig = widget.configs.firstOrNull;
        setState(() {
          _selectedConfig = firstConfig;
        });
        if (firstConfig != null) {
          await _v2rayService.connect(firstConfig);
        }
      }
    });

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
        return Center(
          child: SizedBox(
            width: 50,
            height: 50,
            child: LoadingIndicator(
              indicatorType: Indicator.ballSpinFadeLoader,
              colors: [
                Theme.of(context).colorScheme.onPrimary,
              ], // Use theme color
              strokeWidth: 3,
            ),
          ),
        );
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

  // Show a beautiful snackbar at the top of the screen
  void _showTopSnackBar(
    BuildContext context, {
    required String message,
    required Color backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    // Create a function to remove the overlay
    void removeOverlay() {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    }

    overlayEntry = OverlayEntry(
      builder: (context) => TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta! < -5) {
                  removeOverlay();
                }
              },
              child: Transform.translate(
                offset: Offset(0, (1 - value) * -50),
                child: Opacity(
                  opacity: value,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 24),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Vazirmatn',
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: removeOverlay,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    // Insert the overlay
    overlay.insert(overlayEntry);

    // Auto dismiss after duration
    Future.delayed(duration, removeOverlay);
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

    if (_selectedConfig == null) {
      _showTopSnackBar(
        context,
        message: 'لطفاً ابتدا یک سرور انتخاب کنید.',
        backgroundColor: Theme.of(context).colorScheme.error,
        icon: Icons.error_outline,
      );
      return;
    }

    if (_currentStatus.state == 'DISCONNECTED') {
      // Store connection time when connecting
      _connectionTime = DateTime.now();
    } else if (_currentStatus.state == 'CONNECTED') {
      // Clear connection time when disconnecting
      _connectionTime = null;
    }
  }

  Future<void> _selectServer() async {
    if (_remainingVolumeMB <= 0) {
      _showTopSnackBar(
        context,
        message:
            'اشتراک شما به پایان رسیده است. لطفاً اشتراک خود را تمدید کنید.',
        backgroundColor: Theme.of(context).colorScheme.error,
        icon: Icons.error_outline,
      );
      return;
    }

    if (_currentStatus.state == 'CONNECTED') {
      _showTopSnackBar(
        context,
        message: 'لطفاً ابتدا اتصال را قطع کنید.',
        backgroundColor: Colors.red,
        icon: Icons.warning_amber_rounded,
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            tween: Tween(begin: 0.9, end: 1.0),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated loading indicator
                        Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: LoadingIndicator(
                            indicatorType: Indicator.ballPulse,
                            colors: [Theme.of(context).colorScheme.primary],
                            strokeWidth: 2.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Title with fade animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 500),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 10 * (1 - value)),
                                child: Text(
                                  'در حال دریافت سرورها',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        // Subtitle with delayed animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 500),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            // Add a small delay using a threshold
                            final delayedValue = value < 0.2
                                ? 0.0
                                : (value - 0.2) / 0.8;
                            return Opacity(
                              opacity: delayedValue,
                              child: Transform.translate(
                                offset: Offset(0, 10 * (1 - delayedValue)),
                                child: Text(
                                  'لطفاً شکیبا باشید...',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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

              // Save selected server ID to SharedPreferences
              SharedPreferences.getInstance().then((prefs) {
                prefs.setString('selected_server_id', selected.id);
              });
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _username,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Tooltip(
            message: 'به‌روزرسانی اطلاعات کاربر',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.only(right: 8),
            verticalOffset: 10,
            preferBelow: false,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontFamily: 'Vazirmatn',
            ),
            waitDuration: const Duration(milliseconds: 300),
            showDuration: const Duration(seconds: 2),
            child: IconButton(
              icon: Icon(
                Icons.refresh,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
              onPressed: _fetchUserDetails,
            ),
          ),
        ],
        flexibleSpace: Container(
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
        ),
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
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
              const Divider(color: Colors.white70),
              SizedBox(height: 10),
              Text(
                textAlign: TextAlign.center,
                'Hamed Karimi',
                style: TextStyle(fontFamily: 'Vazirmatn'),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        height: double.infinity,
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
              Consumer<V2RayService>(
                builder: (context, v2rayService, child) {
                  _currentStatus = v2rayService.status;
                  final isConnected = _currentStatus.state == 'CONNECTED';
                  final isConnecting = _currentStatus.state == 'CONNECTING';

                  return TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 500),
                    tween: Tween(begin: 0.95, end: 1.0),
                    curve: Curves.easeOutBack,
                    child: GestureDetector(
                      onTap: _connectDisconnect,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        width: 180,
                        height: 180,
                        margin: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isConnected
                                ? [Colors.green.shade600, Colors.green.shade400]
                                : isConnecting
                                ? [
                                    Colors.orange.shade600,
                                    Colors.orange.shade400,
                                  ]
                                : [
                                    Theme.of(context).primaryColor,
                                    Theme.of(context).colorScheme.secondary,
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isConnected
                                  ? Colors.green.shade300.withOpacity(0.6)
                                  : isConnecting
                                  ? Colors.orange.shade300.withOpacity(0.6)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.6),
                              blurRadius: 25,
                              spreadRadius: 8,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withOpacity(0.9),
                            width: 6,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Pulsing effect when connected
                            if (isConnected)
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 1.0, end: 1.2),
                                duration: const Duration(seconds: 2),
                                curve: Curves.easeInOut,
                                builder: (context, value, child) {
                                  return Container(
                                    width: 180 * value,
                                    height: 180 * value,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.green.withOpacity(0.1),
                                    ),
                                  );
                                },
                              ),
                            // Main content
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Animated icon
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  transitionBuilder: (child, animation) {
                                    return ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    );
                                  },
                                  child: isConnected
                                      ? Icon(
                                          Icons.vpn_key_rounded,
                                          color: Colors.white,
                                          size: 54,
                                          key: const ValueKey('connected'),
                                        )
                                      : isConnecting
                                      ? const SizedBox(
                                          width: 54,
                                          height: 54,
                                          child: LoadingIndicator(
                                            indicatorType:
                                                Indicator.ballSpinFadeLoader,
                                            colors: [Colors.white],
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.vpn_key_off_rounded,
                                          color: Colors.white.withOpacity(0.9),
                                          size: 54,
                                          key: const ValueKey('disconnected'),
                                        ),
                                ),
                                const SizedBox(height: 16),
                                // Status text
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Text(
                                    isConnected
                                        ? 'اتصال برقرار است'
                                        : isConnecting
                                        ? 'در حال اتصال...'
                                        : 'اتصال قطع است',
                                    key: ValueKey(_currentStatus.state),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Vazirmatn',
                                    ),
                                  ),
                                ),
                                // Connection time when connected
                                if (isConnected && _connectionTime != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      _formatDuration(
                                        DateTime.now().difference(
                                          _connectionTime!,
                                        ),
                                      ),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 14,
                                        fontFamily: 'Vazirmatn',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                  );
                },
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

              if (_remainingVolumeMB <= 0)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.error,
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'اشتراک شما به پایان رسیده است',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              else
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 400),
                  tween: Tween(begin: 0.95, end: 1.0),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).primaryColor.withOpacity(0.9),
                          Theme.of(
                            context,
                          ).colorScheme.secondary.withOpacity(0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 1,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: _selectServer,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 20,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.dns_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'سرور انتخاب شده',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 14,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedConfig?.remarks ??
                                          'هیچ سروری انتخاب نشده',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                ),
              SizedBox(height: 20),
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 500),
                tween: Tween(begin: 0.95, end: 1.0),
                curve: Curves.easeOutBack,
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.surface,
                          Theme.of(
                            context,
                          ).colorScheme.surface.withOpacity(0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Consumer<V2RayService>(
                        builder: (context, v2rayService, child) {
                          final isConnected =
                              v2rayService.status.state == 'CONNECTED';
                          final isConnecting =
                              v2rayService.status.state == 'CONNECTING';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isConnected
                                          ? Colors.green.withOpacity(0.1)
                                          : isConnecting
                                          ? Colors.orange.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isConnected
                                          ? Icons.check_circle_outline
                                          : isConnecting
                                          ? Icons.sync
                                          : Icons.error_outline,
                                      color: isConnected
                                          ? Colors.green
                                          : isConnecting
                                          ? Colors.orange
                                          : Colors.red,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'وضعیت اتصال',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurface,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isConnected
                                              ? 'به شبکه متصل هستید'
                                              : isConnecting
                                              ? 'در حال اتصال...'
                                              : 'اتصال برقرار نیست',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.7),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isConnected
                                          ? Colors.green.withOpacity(0.1)
                                          : isConnecting
                                          ? Colors.orange.withOpacity(0.1)
                                          : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      isConnected
                                          ? 'فعال'
                                          : isConnecting
                                          ? 'در حال اتصال'
                                          : 'غیرفعال',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: isConnected
                                                ? Colors.green
                                                : isConnecting
                                                ? Colors.orange
                                                : Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              const Divider(height: 1, thickness: 1.5),
                              const SizedBox(height: 16),

                              // Connection Stats
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                child: isConnected || isConnecting
                                    ? Column(
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildStatItem(
                                                context,
                                                'سرعت دانلود',
                                                '${v2rayService.formatBytes(v2rayService.downloadSpeed)}/ثانیه',
                                                Icons.arrow_downward,
                                                Colors.blue,
                                              ),
                                              _buildStatItem(
                                                context,
                                                'سرعت آپلود',
                                                '${v2rayService.formatBytes(v2rayService.uploadSpeed)}/ثانیه',
                                                Icons.arrow_upward,
                                                Colors.purple,
                                              ),
                                            ],
                                          ),

                                          SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildStatItem(
                                                context,
                                                'کل دانلود',
                                                v2rayService.formatBytes(
                                                  v2rayService.totalDownloaded,
                                                ),
                                                Icons.cloud_download,
                                                Colors.green,
                                              ),
                                              _buildStatItem(
                                                context,
                                                'کل آپلود',
                                                v2rayService.formatBytes(
                                                  v2rayService.totalUploaded,
                                                ),
                                                Icons.cloud_upload,
                                                Colors.orange,
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8.0,
                                        ),
                                        child: Text(
                                          'برای مشاهده آمار اتصال، به یک سرور متصل شوید',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withOpacity(0.6),
                                              ),
                                        ),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
              ),

              // Card(
              //   elevation: 8,
              //   shape: RoundedRectangleBorder(
              //     borderRadius: BorderRadius.circular(20),
              //   ),
              //   margin: const EdgeInsets.only(bottom: 20),
              //   color: _remainingVolumeMB <= 0
              //       ? Theme.of(context).colorScheme.error.withOpacity(0.1)
              //       : null,
              //   child: Padding(
              //     padding: const EdgeInsets.all(20.0),
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         Row(
              //           children: [
              //             Text(
              //               'آمار مصرف:',
              //               style: Theme.of(context).textTheme.titleLarge
              //                   ?.copyWith(
              //                     fontWeight: FontWeight.bold,
              //                     color: _remainingVolumeMB <= 0
              //                         ? Theme.of(context).colorScheme.error
              //                         : Theme.of(context).colorScheme.primary,
              //                   ),
              //             ),
              //             if (_remainingVolumeMB <= 0) ...[
              //               const SizedBox(width: 8),
              //               Icon(
              //                 Icons.warning_amber_rounded,
              //                 color: Theme.of(context).colorScheme.error,
              //               ),
              //             ],
              //           ],
              //         ),
              //         const Divider(height: 20, thickness: 1.5),
              //         _buildInfoRow(
              //           'حجم کلی:',
              //           '${(_totalVolumeMB / 1024).toStringAsFixed(2)} GB',
              //           icon: Icons.storage,
              //           iconColor: Theme.of(context).colorScheme.secondary,
              //         ),
              //         _buildInfoRow(
              //           'حجم مصرفی:',
              //           '${(_usedVolumeMB / 1024).toStringAsFixed(2)} GB',
              //           icon: Icons.pie_chart,
              //           iconColor: Theme.of(context).colorScheme.error,
              //         ),
              //         // NEW: Conditional color for Remaining Volume
              //         _buildInfoRow(
              //           'حجم باقی مانده:',
              //           '${(_remainingVolumeMB / 1024).toStringAsFixed(2)} GB',
              //           icon: Icons.cloud_queue,
              //           iconColor: _remainingVolumeMB <= 0
              //               ? Theme.of(context)
              //                     .colorScheme
              //                     .error // Red if 0 or less
              //               : Theme.of(
              //                   context,
              //                 ).colorScheme.secondary, // Normal color otherwise
              //           valueColor: _remainingVolumeMB <= 0
              //               ? Theme.of(context)
              //                     .colorScheme
              //                     .error // Red text if 0 or less
              //               : Theme.of(
              //                   context,
              //                 ).textTheme.bodyLarge?.color, // Normal text color
              //         ),
              //         // NEW: Conditional color for Remaining Days
              //         _buildInfoRow(
              //           'روزهای باقی مانده:',
              //           '$_remainingDays روز',
              //           icon: Icons.hourglass_empty,
              //           iconColor: _remainingDays <= 0
              //               ? Theme.of(context)
              //                     .colorScheme
              //                     .error // Red if 0 or less
              //               : Theme.of(
              //                   context,
              //                 ).colorScheme.secondary, // Normal color otherwise
              //           valueColor: _remainingDays <= 0
              //               ? Theme.of(context)
              //                     .colorScheme
              //                     .error // Red text if 0 or less
              //               : Theme.of(
              //                   context,
              //                 ).textTheme.bodyLarge?.color, // Normal text color
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
                    color: Theme.of(context).textTheme.bodyMedium?.color,
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
                            '${formatter.yyyy}/${formatter.mm}/${formatter.dd} ${formatter.tH}:${formatter.tM}:${formatter.tS}';
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours.remainder(24));
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
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

  Widget _buildStatItem(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
