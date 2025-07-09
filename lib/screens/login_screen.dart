import 'package:flutter/material.dart';
import 'package:hkray_vpn/services/v2ray_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'vpn_wrapper_screen.dart';
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
          'device_name': deviceName, // Send device name to API
        },
      );

      final responseData = json.decode(response.body);

      if (responseData['success']) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', responseData['user_id']);
        await prefs.setString('username', username);

        // Send login status with device name
        await Provider.of<V2RayService>(
          context,
          listen: false,
        ).sendLoginStatus(responseData['user_id'], true, deviceName);

        // ignore: use_build_context_synchronously
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const VpnWrapperScreen()),
        );
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData['message'] ?? 'خطای ناشناخته')),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در برقراری ارتباط: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Logo/App Icon
              Icon(
                Icons.vpn_lock, // Or your app's specific icon
                size: 100,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'به HKRay VPN خوش آمدید',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onBackground,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'نام کاربری',
                  hintText: 'نام کاربری خود را وارد کنید',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'رمز عبور',
                  hintText: 'رمز عبور خود را وارد کنید',
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('ورود'),
                    ),
              const SizedBox(height: 20), // Added spacing
            ],
          ),
        ),
      ),
    );
  }
}
