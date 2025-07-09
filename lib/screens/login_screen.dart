import 'package:flutter/material.dart';
import 'package:hkray_vpn/services/v2ray_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'vpn_wrapper_screen.dart';
import 'dart:io'; // For Platform.isAndroid, Platform.isIOS
import 'package:device_info_plus/device_info_plus.dart'; // اضافه کردن این import

/// A screen that provides a login interface for users to authenticate.
///
/// This widget manages user input for username and password, and
/// interacts with the authentication service to verify credentials.
/// After successful login, the user is navigated to the main VPN
/// wrapper screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  final String _apiBaseUrl = 'https://blizzardping.ir/api.php'; // آدرس API شما

  // Function to get the actual device name using device_info_plus
  Future<String> _getDeviceName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model; // مدل دستگاه اندروید
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.name; // نام دستگاه iOS
    } else if (Platform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
      return linuxInfo.prettyName; // نام سیستم لینوکس
    } else if (Platform.isMacOS) {
      MacOsDeviceInfo macOsInfo = await deviceInfo.macOsInfo;
      return macOsInfo.model; // مدل دستگاه مک
    } else if (Platform.isWindows) {
      WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
      return windowsInfo.computerName; // نام کامپیوتر ویندوز
    }
    return 'Unknown Device'; // برای پلتفرم‌های دیگر
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final username = _usernameController.text;
    final password = _passwordController.text;
    final deviceName = await _getDeviceName(); // دریافت نام واقعی دستگاه

    if (username.isEmpty || password.isEmpty) {
      _showSnackBar('لطفا نام کاربری و رمز عبور را وارد کنید.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final url = Uri.parse('$_apiBaseUrl?action=login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': username,
          'password': password,
          'device_name': deviceName, // ارسال نام واقعی دستگاه
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final userId = responseData['user_id'];
          final fetchedUsername = responseData['username'];

          await prefs.setInt('user_id', userId);
          await prefs.setString('username', fetchedUsername);

          // Get V2RayService instance
          final v2rayService = Provider.of<V2RayService>(
            context,
            listen: false,
          );

          // Send login status to server including device name
          print(
            'LoginScreen: Calling sendLoginStatus for user ID: $userId, isLoggedIn: true, deviceName: $deviceName',
          );
          await v2rayService.sendLoginStatus(
            userId,
            true,
            deviceName,
          ); // Pass deviceName

          // Navigate to VPNWrapperScreen
          // ignore: use_build_context_synchronously
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const VpnWrapperScreen()),
          );
        } else {
          _showSnackBar(responseData['message'] ?? 'خطای ناشناخته در ورود.');
        }
      } else {
        _showSnackBar('خطا در اتصال به سرور: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('خطا در ورود: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueAccent.shade700, Colors.blueAccent.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png', // مسیر لوگوی شما
                      height: 120,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'ورود به حساب کاربری',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent.shade700,
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'نام کاربری',
                        prefixIcon: Icon(
                          Icons.person,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'رمز عبور',
                        prefixIcon: Icon(Icons.lock, color: Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(height: 30),
                    _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.blueAccent,
                          )
                        : SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _login,
                              child: const Text(
                                'ورود',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
