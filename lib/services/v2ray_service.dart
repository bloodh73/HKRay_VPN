import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/v2ray_config.dart';
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler

class V2RayService with ChangeNotifier {
  late final FlutterV2ray _v2ray;

  // Track if V2Ray is initialized
  bool _isInitialized = false;
  bool _isConnected = false;
  V2RayConfig? _currentConfig;
  V2RayStatus _status = V2RayStatus(state: 'IDLE');
  final StreamController<V2RayStatus> _statusController =
      StreamController<V2RayStatus>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  // API base URL
  final String _apiBaseUrl = 'https://blizzardping.ir/api.php'; // آدرس API شما

  // Traffic and ping variables
  int _downloadSpeed = 0; // in bytes per second
  int _uploadSpeed = 0; // in bytes per second
  int _ping = 0; // in milliseconds  // Track traffic
  int _totalUploaded = 0;
  int _totalDownloaded = 0;
  int _lastReportedUpload = 0;
  int _lastReportedDownload = 0;
  DateTime? _lastTrafficUpdate;

  // Data usage tracking
  Timer? _trafficReportTimer;
  Timer? _trafficUpdateTimer;
  static const int _reportIntervalSeconds = 10; // 5 minutes

  // --- Performance Improvement: UI Update Throttling ---
  Timer? _uiUpdateThrottleTimer;
  bool _isThrottling = false;
  // ----------------------------------------------------

  Stream<V2RayStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  bool get isConnected => _isConnected;
  V2RayConfig? get currentConfig => _currentConfig;
  V2RayStatus get status => _status;
  int get downloadSpeed => _downloadSpeed;
  int get uploadSpeed => _uploadSpeed;
  int get ping => _ping;
  int get totalDownloaded => _totalDownloaded;
  int get totalUploaded => _totalUploaded;

  V2RayService() {
    _v2ray = FlutterV2ray(
      onStatusChanged: (status) {
        try {
          // Check if the core connection state has changed (e.g., CONNECTED -> DISCONNECTED)
          final bool stateChanged = _status.state != status.state;

          // Always update the internal status object with the latest data
          _status = status;
          _handleStatusChange(status);
          _statusController.add(status);

          // If the major state has changed, notify listeners immediately.
          if (stateChanged) {
            _logController.add(
              'V2Ray connection state changed to: ${status.state}',
            );
            if (status.state == 'CONNECTED' && !_isConnected) {
              _isConnected = true;
              _startTrafficUploadTimer();
            } else if (status.state == 'DISCONNECTED' && _isConnected) {
              _isConnected = false;
              _stopTrafficUploadTimer();
              _ping = 0;
              // Report final traffic before disconnecting
              _reportTrafficToServer();
            }
            notifyListeners(); // Notify for major state changes
          } else {
            // If only traffic stats have changed, throttle UI updates to avoid jank.
            _throttleUiUpdate();
          }
        } catch (e, stackTrace) {
          _logController.add('Error in status change handler: $e\n$stackTrace');
        }
      },
    );

    _initializeV2Ray();
  }

  /// Throttles calls to notifyListeners() to at most once per second.
  /// This prevents the UI from rebuilding too frequently with traffic updates.
  void _throttleUiUpdate() {
    if (!_isThrottling) {
      _isThrottling = true;
      _uiUpdateThrottleTimer = Timer(const Duration(seconds: 1), () {
        notifyListeners();
        _isThrottling = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    _logController.add(
      'V2Ray Log: _requestNotificationPermission called.',
    ); // این خط را اضافه کنید

    final status = await Permission.notification.status;
    if (status.isGranted) {
      _logController.add('V2Ray Log: Notification permission granted.');
    } else if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        _logController.add(
          'V2Ray Log: Notification permission granted after request.',
        );
      } else {
        _logController.add(
          'V2Ray Log: Notification permission denied. Notifications may not show.',
        );
      }
    } else if (status.isPermanentlyDenied) {
      _logController.add(
        'V2Ray Log: Notification permission permanently denied. User needs to enable it from settings.',
      );
      // Optionally, open app settings: openAppSettings();
    } else {
      _logController.add('V2Ray Log: Notification permission status: $status');
    }
  }

  Future<void> _initializeV2Ray() async {
    try {
      // درخواست مجوز نوتیفیکیشن قبل از شروع V2Ray
      await _requestNotificationPermission();

      // شروع V2Ray با تنظیمات نوتیفیکیشن
      await _v2ray.initializeV2Ray(
        notificationIconResourceType: "mipmap",
        notificationIconResourceName: "ic_launcher",
      );
      _isInitialized = true;
      _logController.add('V2Ray service initialized');
      notifyListeners(); // اضافه شده: اطلاع‌رسانی پس از موفقیت‌آمیز بودن مقداردهی اولیه

      // ... rest of the method
    } catch (e) {
      // ... error handling
    }
  }

  /// [NEW METHOD] Measures the real delay of a server by connecting and making a request.
  /// Returns the delay in milliseconds, or a negative value on error.
  Future<int> getRealPing(V2RayConfig config) async {
    try {
      if (!_isInitialized) {
        _logController.add('V2Ray not initialized, cannot get server delay.');
        await _initializeV2Ray(); // Attempt to initialize if not already
        if (!_isInitialized) return -99;
      }
      _logController.add('Getting real server delay for: ${config.name}');
      // This method internally connects, tests, and disconnects.
      final delay = await _v2ray.getServerDelay(config: config.fullConfigJson);
      _logController.add('Real delay for ${config.name}: $delay ms');
      return delay;
    } catch (e) {
      _logController.add('Error getting server delay for ${config.name}: $e');
      return -1; // General error
    }
  }

  void _handleStatusChange(V2RayStatus status) {
    _status = status;
    if (status.state == 'CONNECTED' && !_isConnected) {
      _isConnected = true;
      _startTrafficUploadTimer();
    } else if (status.state == 'DISCONNECTED' && _isConnected) {
      _isConnected = false;
      _stopTrafficUploadTimer();
      _ping = 0;
      // Report final traffic before disconnecting
      _reportTrafficToServer();
    }
  }

  void _startTrafficUploadTimer() {
    // Cancel any existing timers
    _stopTrafficUploadTimer();

    // Initialize traffic stats
    _lastReportedUpload = _totalUploaded;
    _lastReportedDownload = _totalDownloaded;
    _lastTrafficUpdate = DateTime.now();

    // Start periodic traffic reporting to server
    _trafficReportTimer = Timer.periodic(
      const Duration(seconds: _reportIntervalSeconds),
      (timer) => _reportTrafficToServer(),
    );

    // Update UI and local stats more frequently
    _trafficUpdateTimer = Timer.periodic(
      const Duration(seconds: 5), // Update every 5 seconds for smoother UI
      (timer) {
        _updateTrafficStats(_status.upload, _status.download);
      },
    );

    _logController.add('Started traffic monitoring');

    _logController.add('Started traffic monitoring');
  }

  void _stopTrafficUploadTimer() {
    _trafficReportTimer?.cancel();
    _trafficReportTimer = null;
    _trafficUpdateTimer?.cancel();
    _trafficUpdateTimer = null;
  }

  // Report traffic usage to the server
  Future<void> _reportTrafficToServer() async {
    if (!_isConnected || _currentConfig == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Get user ID
    final userId = prefs.getInt('user_id');
    if (userId == null) {
      _logController.add('User ID not found, skipping traffic report');
      return;
    }

    // Get token with proper type checking
    String? token;
    try {
      token = prefs.getString('token');
      _logController.add(
        'Token retrieved: ${token != null ? 'Token exists' : 'No token found'}',
      );
      if (token != null) {
        _logController.add('Token length: ${token.length}');
      }
    } catch (e) {
      _logController.add('Error reading token: $e');
    }

    final uploaded = _totalUploaded - _lastReportedUpload;
    final downloaded = _totalDownloaded - _lastReportedDownload;

    if (uploaded <= 0 && downloaded <= 0) {
      return; // No new data to report
    }

    try {
      // Log token status
      _logController.add(
        'Token status: ${token != null && token.isNotEmpty ? 'Available' : 'Missing or empty'}',
      );
      if (token != null && token.isNotEmpty) {
        _logController.add('Token length: ${token.length}');
      }

      _logController.add(
        'Raw traffic - Uploaded: $uploaded bytes, Downloaded: $downloaded bytes',
      );

      // Build the base URL with action and user_id as query parameters
      final queryParams = <String, String>{
        // Corrected action from 'update_usage' to 'updateTraffic'
        'action': 'updateTraffic',
        'user_id': userId.toString(),
      };

      // Add token to query params if available
      if (token != null && token.isNotEmpty) {
        queryParams['token'] = token;
      }

      final uri = Uri.parse(_apiBaseUrl).replace(queryParameters: queryParams);

      // Log the exact URL being called (without token for security)
      _logController.add('API Endpoint: ${uri.origin}${uri.path}');
      _logController.add(
        'Query Params: ${uri.queryParameters.keys.join(', ')}',
      );

      // Prepare the request body with bytes and additional required fields
      final requestData = {
        'bytes': (uploaded + downloaded).toString(),
        // Corrected keys from 'uploaded' to 'upload' and 'downloaded' to 'download'
        'upload': uploaded.toString(),
        'download': downloaded.toString(),
        'server': _currentConfig?.id ?? '',
        'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      };

      _logController.add('Request data: $requestData');

      // Send as form data with explicit content type
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: requestData,
      );

      // Log raw response for debugging
      _logController.add(
        'Raw response: ${response.statusCode} ${response.body}',
      );

      _logController.add('Server response status: ${response.statusCode}');
      _logController.add('Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body);
          if (result is Map && result['success'] == true) {
            _lastReportedUpload = _totalUploaded;
            _lastReportedDownload = _totalDownloaded;
            _logController.add('Successfully reported traffic usage');
          } else {
            _logController.add(
              'Server reported error: ${result['message'] ?? 'Unknown error'}',
            );
          }
        } catch (e) {
          _logController.add('Error parsing server response: $e');
          _logController.add('Raw response: ${response.body}');
        }
      } else {
        _logController.add(
          'HTTP error ${response.statusCode} when reporting traffic',
        );
      }
    } catch (e) {
      _logController.add('Error reporting traffic: $e');
    }
  }

  // Update traffic stats
  void _updateTrafficStats(int upload, int download) {
    if (upload < 0 || download < 0) return; // Skip invalid values

    final now = DateTime.now();

    // Calculate speeds if we have a previous update
    if (_lastTrafficUpdate != null) {
      final timeDiff =
          now.difference(_lastTrafficUpdate!).inMilliseconds / 1000;
      if (timeDiff > 0) {
        _uploadSpeed = ((upload - _totalUploaded) / timeDiff).round();
        _downloadSpeed = ((download - _totalDownloaded) / timeDiff).round();
      }
    }

    _totalUploaded = upload;
    _totalDownloaded = download;
    _lastTrafficUpdate = now;

    // Throttle UI updates
    _throttleUiUpdate();
  }

  String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  /// Sends the user's login status and last login timestamp to the server.
  /// This helps in tracking active sessions and user activity.
  Future<void> sendLoginStatus(
    int userId,
    bool isLoggedIn,
    String deviceName,
  ) async {
    try {
      // Build the URL with 'action' as a query parameter
      final queryParams = <String, String>{
        'action': 'updateLoginStatus', // Action as query parameter
      };
      final url = Uri.parse(_apiBaseUrl).replace(queryParameters: queryParams);

      _logController.add('V2Ray Log: Sending login status to API: $url');
      _logController.add(
        'V2Ray Log: Login status data: userId=$userId, isLoggedIn=$isLoggedIn, deviceName=$deviceName',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'user_id': userId.toString(),
          'is_logged_in': isLoggedIn ? '1' : '0', // Send as '1' or '0'
          'last_login': DateTime.now().toIso8601String(), // ISO 8601 format
          'device_name': deviceName, // Send the device name
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          _logController.add(
            'V2Ray Log: Successfully updated login status on server: $isLoggedIn',
          );
        } else {
          _logController.add(
            'V2Ray Log: Server error updating login status: ${responseData['message'] ?? 'Unknown error'}',
          );
        }
      } else {
        _logController.add(
          'V2Ray Log: HTTP error ${response.statusCode} when updating login status',
        );
      }
    } catch (e, stackTrace) {
      _logController.add(
        'V2Ray Log: Error sending login status: $e\n$stackTrace',
      );
    }
  }

  bool _isConnecting = false;
  DateTime? _lastConnectionAttempt;

  Future<bool> _checkAndRequestNotificationPermission() async {
    if (!Platform.isAndroid) return true; // Only applicable to Android

    try {
      // Check if we have notification permission
      var status = await Permission.notification.status;
      if (status.isDenied) {
        // Request the permission
        status = await Permission.notification.request();
        if (status.isDenied) {
          _logController.add(
            'Notification permission is required for VPN connection',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      _logController.add('Error checking notification permission: $e');
      return true; // Continue anyway if we can't check
    }
  }

  // Changed to accept V2RayConfig object instead of a URI string
  Future<bool> connect(V2RayConfig config) async {
    try {
      // Prevent multiple simultaneous connection attempts
      if (_isConnecting) {
        _logController.add('Connection attempt already in progress');
        return false;
      }

      // Check and request notification permission for Android 13+
      if (!await _checkAndRequestNotificationPermission()) {
        _logController.add('Notification permission is required');
        return false;
      }

      // Prevent rapid reconnection attempts
      if (_lastConnectionAttempt != null &&
          DateTime.now().difference(_lastConnectionAttempt!) <
              const Duration(seconds: 5)) {
        _logController.add('Please wait before reconnecting');
        return false;
      }

      _isConnecting = true;
      _lastConnectionAttempt = DateTime.now();
      _logController.add('Starting V2Ray connection...');

      if (!_isInitialized) {
        _logController.add('Initializing V2Ray service...');
        await _initializeV2Ray();
        if (!_isInitialized) {
          _logController.add('Failed to initialize V2Ray service');
          _isConnecting = false;
          return false;
        }
      }

      // Directly use the provided config object
      _currentConfig = config;
      final String fullConfigJson = config.fullConfigJson;
      final String remark = config.remarks ?? config.name;

      _handleStatusChange(V2RayStatus(state: 'CONNECTING'));

      // Request VPN permission
      final hasPermission = await _v2ray.requestPermission();
      if (!hasPermission) {
        _logController.add('VPN permission not granted');
        _handleStatusChange(V2RayStatus(state: 'DISCONNECTED'));
        _isConnecting = false;
        return false;
      }

      // Log the full configuration for debugging
      _logController.add('Using V2Ray config: $fullConfigJson');

      try {
        // Start V2Ray with configuration
        _logController.add('Starting V2Ray with configuration...');
        await _v2ray.startV2Ray(
          remark: remark,
          config: fullConfigJson,
          blockedApps: null,
          bypassSubnets: null,
          proxyOnly: false,
        );
        _logController.add('V2Ray started successfully');
      } catch (e, stackTrace) {
        _logController.add('Error starting V2Ray: $e');
        _logController.add('Stack trace: $stackTrace');
        rethrow;
      }

      // Save this config as last used
      await _saveLastUsedConfig(_currentConfig!);
      _isConnecting = false;
      return true;
    } catch (e, stackTrace) {
      _logController.add('Error connecting to server: $e\n$stackTrace');
      _status = V2RayStatus(state: 'ERROR');
      _isConnected = false;
      _isConnecting = false;
      _statusController.add(_status);
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      _logController.add('Disconnecting from server...');
      await _v2ray.stopV2Ray();
      _status = V2RayStatus(state: 'DISCONNECTED');
      _statusController.add(_status);
      _logController.add('Disconnected from server');
    } catch (e, stackTrace) {
      _logController.add('Error disconnecting from V2Ray: $e\n$stackTrace');
      _status = V2RayStatus(state: 'ERROR');
      _isConnected = false;
      _statusController.add(_status);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _saveLastUsedConfig(V2RayConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_used_config', jsonEncode(config.toJson()));
    } catch (e) {
      _logController.add('Error saving last used config: $e');
    }
  }

  Future<V2RayConfig?> getLastUsedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString('last_used_config');
      if (configJson != null) {
        return V2RayConfig.fromJson(jsonDecode(configJson));
      }
    } catch (e) {
      _logController.add('Error loading last used config: $e');
    }
    return null;
  }

  // اضافه شدن متد جدید برای واکشی لیست دستگاه‌های وارد شده
  // این متد اکنون username را به عنوان پارامتر دریافت می‌کند
  Future<List<Map<String, dynamic>>> fetchLoggedInDevices(
    String username,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt(
        'user_id',
      ); // Get user ID from SharedPreferences

      if (userId == null) {
        _logController.add(
          'User ID not found in SharedPreferences for fetching devices.',
        );
        return []; // Cannot fetch devices without user ID
      }

      // URL اکنون شامل username و user_id است
      final url = Uri.parse(
        '$_apiBaseUrl?action=getLoggedInDevices&username=$username&user_id=$userId',
      );
      _logController.add('Fetching logged-in devices from API: $url');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _logController.add(
          'Received response for logged-in devices: ${response.body}',
        );
        if (responseData['success'] == true) {
          if (responseData['devices'] is List) {
            // Correctly parse as List of Map<String, dynamic>
            final devices = List<Map<String, dynamic>>.from(
              responseData['devices'],
            );
            _logController.add(
              'Successfully parsed ${devices.length} logged-in devices.',
            );
            return devices;
          } else {
            _logController.add(
              'Error: "devices" is not a list in API response for logged-in devices.',
            );
            return [];
          }
        } else {
          _logController.add(
            'Server error fetching devices: ${responseData['message'] ?? 'Unknown error'}',
          );
          return [];
        }
      } else {
        _logController.add(
          'HTTP error ${response.statusCode} fetching devices',
        );
        return [];
      }
    } catch (e, stackTrace) {
      _logController.add('Error fetching logged in devices: $e\n$stackTrace');
      return [];
    }
  }

  @override
  void dispose() {
    try {
      _logController.add('Disposing V2Ray service...');

      // Send final traffic report
      if (_isConnected) {
        _sendTrafficUpdateToServer().catchError((e) {
          _logController.add('Error sending final traffic report: $e');
        });
      }

      // Cancel all timers
      _stopTrafficUploadTimer();
      _uiUpdateThrottleTimer?.cancel();

      // Close controllers
      _statusController.close();
      _logController.close();

      super.dispose();
      _logController.add('V2Ray service disposed');
    } catch (e, stackTrace) {
      _logController.add('Error disposing V2Ray service: $e\n$stackTrace');
      rethrow;
    }
  }

  // The _sendTrafficUpdateToServer method is defined here
  Future<void> _sendTrafficUpdateToServer() async {
    try {
      await _reportTrafficToServer();
    } catch (e) {
      _logController.add('Error sending traffic update: $e');
    }
  }
}
