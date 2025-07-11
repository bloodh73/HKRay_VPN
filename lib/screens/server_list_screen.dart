// server_list_screen.dart
import 'package:flutter/material.dart';
import '../models/v2ray_config.dart';
import 'dart:io'; // برای Socket.connect جهت اندازه‌گیری پینگ TCP
import 'dart:async'; // برای TimeoutException

class ServerListScreen extends StatefulWidget {
  final List<V2RayConfig> configs;
  final V2RayConfig? currentSelectedConfig;

  const ServerListScreen({
    Key? key,
    required this.configs,
    this.currentSelectedConfig,
  }) : super(key: key);

  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  V2RayConfig? _selectedConfig;
  final Map<String, int?> _serverPings = {};
  final Map<String, bool> _isPingingServer = {};
  // اضافه شدن نقشه برای ذخیره زمان آخرین تلاش پینگ
  final Map<String, DateTime> _lastPingAttemptTime = {};
  // مدت زمان وقفه برای پینگ‌های ناموفق
  static const Duration _pingCooldownDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.currentSelectedConfig;

    _pingAllServers();

    print('ServerListScreen - Received ${widget.configs.length} configs');
    widget.configs.asMap().forEach((index, config) {
      print(
        'Server $index: ${config.name} - ${config.server}:${config.port}', // Changed to config.name
      );
    });
  }

  Future<void> _pingAllServers() async {
    for (var config in widget.configs) {
      // بررسی می‌کنیم که آیا سرور در حال پینگ شدن است یا خیر
      // و همچنین آیا باید پینگ شود (بر اساس مکانیزم Cooldown برای پینگ‌های ناموفق)
      if (!_isPingingServer.containsKey(config.id) ||
          !_isPingingServer[config.id]!) {
        // بررسی وضعیت پینگ قبلی و زمان آخرین تلاش
        final currentPingResult = _serverPings[config.id];
        final lastAttempt = _lastPingAttemptTime[config.id];

        // اگر پینگ قبلی ناموفق بوده و هنوز در دوره Cooldown هستیم، پینگ را رد می‌کنیم
        if (currentPingResult != null &&
            (currentPingResult == -1 ||
                currentPingResult == -2 ||
                currentPingResult == -3) &&
            lastAttempt != null &&
            DateTime.now().difference(lastAttempt) < _pingCooldownDuration) {
          print(
            'Skipping ping for ${config.name} (${config.id}) due to cooldown after recent failure.',
          );
          continue; // به سرور بعدی می‌رویم
        }
        _pingServer(config);
      }
    }
  }

  Future<void> _pingServer(V2RayConfig config) async {
    if (_isPingingServer[config.id] == true)
      return; // اگر در حال پینگ شدن است، کاری نمی‌کنیم

    setState(() {
      _isPingingServer[config.id] = true;
      _serverPings[config.id] = null; // پاک کردن پینگ قبلی
    });

    try {
      final host = config.server;
      final port = config.port;
      final startTime = DateTime.now();

      // تلاش برای اتصال به هاست و پورت سرور
      // استفاده از تایم اوت برای جلوگیری از انتظار نامحدود
      await Socket.connect(host, port, timeout: const Duration(seconds: 5));

      final endTime = DateTime.now();
      final pingTime = endTime.difference(startTime).inMilliseconds;

      setState(() {
        _serverPings[config.id] = pingTime;
      });
    } on SocketException catch (e) {
      print('Ping failed for ${config.server}:${config.port}: $e');
      setState(() {
        _serverPings[config.id] = -1; // نشان دهنده خطا
      });
    } on TimeoutException {
      print('Ping timed out for ${config.server}:${config.port}');
      setState(() {
        _serverPings[config.id] = -2; // نشان دهنده تایم اوت
      });
    } catch (e) {
      print(
        'An unexpected error occurred during ping for ${config.server}:${config.port}: $e',
      );
      setState(() {
        _serverPings[config.id] = -3; // نشان دهنده خطای دیگر
      });
    } finally {
      setState(() {
        _isPingingServer[config.id] = false;
        _lastPingAttemptTime[config.id] =
            DateTime.now(); // ذخیره زمان آخرین تلاش پینگ
      });
    }
  }

  String _getPingText(int? ping) {
    if (ping == null) return 'در حال پینگ...';
    if (ping == -1) return 'خطا';
    if (ping == -2) return 'تایم اوت';
    if (ping == -3) return 'خطای ناشناخته';
    return '$ping ms';
  }

  Color _getPingColor(int? ping) {
    if (ping == null) return Colors.grey;
    if (ping == -1 || ping == -2 || ping == -3) return Colors.red;
    if (ping < 100) return Colors.green;
    if (ping < 200) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'انتخاب سرور',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context, _selectedConfig);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              // وقتی دکمه رفرش فشار داده می‌شود، همه سرورها را بدون توجه به Cooldown پینگ می‌کنیم
              _serverPings.clear(); // پاک کردن نتایج پینگ قبلی
              _lastPingAttemptTime.clear(); // پاک کردن زمان آخرین تلاش
              _pingAllServers(); // فراخوانی مجدد پینگ برای همه
            },
            tooltip: 'پینگ مجدد همه سرورها',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: widget.configs.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.sentiment_dissatisfied,
                      size: 80,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'هیچ سروری برای نمایش وجود ندارد.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Optionally, navigate back or refresh the main screen
                        Navigator.pop(context); // Go back to HomeScreen
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('بازگشت'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: widget.configs.length,
                itemBuilder: (context, index) {
                  final config = widget.configs[index];
                  final isSelected = _selectedConfig?.id == config.id;
                  final serverPing = _serverPings[config.id];
                  final isPinging = _isPingingServer[config.id] == true;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: isSelected
                          ? BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                              width: 2,
                            )
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      leading: Icon(
                        Icons.vpn_lock,
                        color: isSelected
                            ? Theme.of(context).colorScheme.secondary
                            : Colors.blueGrey,
                        size: 30,
                      ),
                      title: Text(
                        // نمایش فیلد 'name' که اکنون دارای fallback است
                        config.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.blueAccent.shade700
                                  : Colors.black87,
                            ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${config.protocol?.toUpperCase() ?? 'نامشخص'} - ${config.server}:${config.port}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.network_check,
                                size: 16,
                                color: _getPingColor(serverPing),
                              ),
                              const SizedBox(width: 4),
                              if (isPinging)
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Theme.of(context).colorScheme.secondary,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'پینگ: ${_getPingText(serverPing)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: _getPingColor(serverPing),
                                      ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.secondary,
                              size: 30,
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedConfig = config;
                        });
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
