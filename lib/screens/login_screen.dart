import 'package:HKRay_vpn/services/v2ray_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'splash_screen.dart'; // Changed to SplashScreen as it's the new entry point
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  final String _apiBaseUrl = 'https://blizzardping.ir/api.php';

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

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final String username = _usernameController.text;
    final String password = _passwordController.text;
    final String deviceName = await _getDeviceName();

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl?action=login'),
        body: {
          'username': username,
          'password': password,
          'device_name': deviceName,
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        if (responseData['success']) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', responseData['user_id']);
          await prefs.setString('username', username);

          if (responseData['token'] != null) {
            await prefs.setString('token', responseData['token']);
            print('Token saved successfully.');
          } else {
            print('Token not found in login response.');
          }

          // ignore: use_build_context_synchronously
          await Provider.of<V2RayService>(
            context,
            listen: false,
          ).sendLoginStatus(responseData['user_id'], true, deviceName);

          // After successful login, navigate back to SplashScreen to re-check status
          // ignore: use_build_context_synchronously
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const SplashScreen(),
            ), // Navigate to SplashScreen
          );
        } else {
          // ignore: use_build_context_synchronously
          _showErrorDialog(responseData['message'] ?? 'خطای ناشناخته');
        }
      } else {
        // ignore: use_build_context_synchronously
        _showErrorDialog('خطا در اتصال به سرور: ${response.statusCode}');
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      _showErrorDialog('خطا در برقراری ارتباط: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'خطا',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        actions: <Widget>[
          TextButton(
            child: Text(
              'باشه',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
            },
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        backgroundColor: Theme.of(context).cardTheme.color,
        elevation: 10,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.onPrimary,
                      Theme.of(context).colorScheme.onSurface,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Text(
                    'HKRay VPN',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary, // This color is masked by shader
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'به دنیای اینترنت آزاد خوش آمدید',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 48),
                TextField(
                  cursorColor: Colors.white,
                  controller: _usernameController,
                  decoration: InputDecoration(
                    // labelText: 'نام کاربری',
                    hintText: 'نام کاربری خود را وارد کنید',
                    prefixIcon: Icon(
                      Icons.person,
                      color: Theme.of(
                        context,
                      ).inputDecorationTheme.prefixIconColor,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  cursorColor: Colors.white,
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    // labelText: 'رمز عبور',
                    hintText: 'رمز عبور خود را وارد کنید',
                    prefixIcon: Icon(
                      Icons.lock,
                      color: Theme.of(
                        context,
                      ).inputDecorationTheme.prefixIconColor,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                _isLoading
                    ? CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(
                            context,
                          ).colorScheme.onPrimary.withOpacity(0.9),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).colorScheme.secondary,
                              Theme.of(context).primaryColor,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).shadowColor.withOpacity(0.2),
                              spreadRadius: 2,
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            'ورود',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
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
}
