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
  // نقشه‌ای برای ذخیره نتایج پینگ هر سرور (ID سرور به میلی‌ثانیه)
  final Map<String, int?> _serverPings = {};
  // نقشه‌ای برای ردیابی وضعیت پینگ هر سرور (ID سرور به وضعیت در حال پینگ)
  final Map<String, bool> _isPingingServer = {};

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.currentSelectedConfig;

    // شروع اندازه‌گیری پینگ برای هر سرور
    _pingAllServers();

    // Debug print to check received configs
    print('ServerListScreen - Received ${widget.configs.length} configs');
    widget.configs.asMap().forEach((index, config) {
      print(
        'Server $index: ${config.remarks} - ${config.server}:${config.port}',
      );
    });
  }

  /// متد کمکی برای شروع پینگ برای همه سرورها
  void _pingAllServers() {
    for (var config in widget.configs) {
      _measureServerPing(config);
    }
  }

  /// اندازه‌گیری پینگ TCP به آدرس و پورت سرور مشخص شده.
  /// این متد تأخیر شبکه مستقیم تا سرور را اندازه‌گیری می‌کند.
  Future<void> _measureServerPing(V2RayConfig config) async {
    // وضعیت در حال پینگ را برای این سرور تنظیم کنید
    setState(() {
      _isPingingServer[config.id] = true;
      _serverPings[config.id] = null; // پاک کردن پینگ قبلی
    });

    try {
      final stopwatch = Stopwatch()..start(); // شروع کرونومتر
      // تلاش برای برقراری اتصال TCP با یک مهلت زمانی
      final socket = await Socket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 5), // مهلت 5 ثانیه برای اتصال
      );
      stopwatch.stop(); // توقف کرونومتر
      socket.destroy(); // بلافاصله سوکت را ببندید

      // به روز رسانی نتیجه پینگ
      setState(() {
        _serverPings[config.id] = stopwatch.elapsedMilliseconds;
      });
    } on SocketException catch (e) {
      // خطای سوکت (مانند عدم دسترسی به میزبان، اتصال رد شده)
      print('Error pinging ${config.server}:${config.port}: $e');
      setState(() {
        _serverPings[config.id] = -1; // نشان دهنده خطا
      });
    } on TimeoutException catch (_) {
      // خطای مهلت زمانی
      print('Ping timeout for ${config.server}:${config.port}');
      setState(() {
        _serverPings[config.id] = -2; // نشان دهنده مهلت زمانی
      });
    } catch (e) {
      // هر خطای غیرمنتظره دیگر
      print('Unexpected error pinging ${config.server}:${config.port}: $e');
      setState(() {
        _serverPings[config.id] = -3; // نشان دهنده خطای دیگر
      });
    } finally {
      // پایان وضعیت در حال پینگ
      setState(() {
        _isPingingServer[config.id] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _selectedConfig);
        return false; // جلوگیری از رفتار پیش‌فرض دکمه بازگشت
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('انتخاب سرور'), // عنوان ساده، پینگ جهانی حذف شد
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _selectedConfig),
          ),
          actions: [
            if (_selectedConfig != null)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  Navigator.pop(context, _selectedConfig);
                },
              ),
            // دکمه رفرش برای پینگ مجدد همه سرورها
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _pingAllServers,
            ),
          ],
        ),
        body: widget.configs.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'هیچ سروری یافت نشد.',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('تلاش مجدد'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: widget.configs.length,
                itemBuilder: (context, index) {
                  final config = widget.configs[index];
                  final isSelected = _selectedConfig?.id == config.id;
                  final serverPing = _serverPings[config.id];
                  final isPinging = _isPingingServer[config.id] ?? false;

                  return Card(
                    elevation: isSelected ? 8 : 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: isSelected
                          ? const BorderSide(color: Colors.blueAccent, width: 2)
                          : BorderSide.none,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Icon(
                        Icons.vpn_lock,
                        color: isSelected ? Colors.blueAccent : Colors.grey,
                        size: 30,
                      ),
                      title: Text(
                        config.remarks ?? 'سرور نامشخص',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.blueAccent
                                  : Colors.black87,
                            ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${config.server}:${config.port} • ${config.protocol?.toUpperCase() ?? 'VMESS'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          // نمایش وضعیت پینگ
                          if (isPinging)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blueAccent,
                              ),
                            )
                          else if (serverPing != null && serverPing >= 0)
                            Text(
                              'پینگ: $serverPing میلی‌ثانیه',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                            )
                          else if (serverPing == -1)
                            Text(
                              'پینگ: خطا (اتصال)',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.red[700]),
                            )
                          else if (serverPing == -2)
                            Text(
                              'پینگ: Timeout',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.orange[700]),
                            )
                          else if (serverPing == -3)
                            Text(
                              'پینگ: خطا',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.red[700]),
                            ),
                        ],
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 28,
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
