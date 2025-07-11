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

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.currentSelectedConfig;

    _pingAllServers();

    print('ServerListScreen - Received ${widget.configs.length} configs');
    widget.configs.asMap().forEach((index, config) {
      print(
        'Server $index: ${config.remarks} - ${config.server}:${config.port}',
      );
    });
  }

  Future<void> _pingAllServers() async {
    for (var config in widget.configs) {
      if (!_isPingingServer.containsKey(config.id) || !_isPingingServer[config.id]!) {
        _pingServer(config);
      }
    }
  }

  Future<void> _pingServer(V2RayConfig config) async {
    if (mounted) {
      setState(() {
        _isPingingServer[config.id] = true;
        _serverPings[config.id] = null; // نشانگر در حال پینگ
      });
    }

    try {
      final stopwatch = Stopwatch()..start();
      final socket = await Socket.connect(
        config.server,
        config.port,
        timeout: const Duration(seconds: 5), // مهلت 5 ثانیه
      );
      socket.destroy();
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _serverPings[config.id] = stopwatch.elapsedMilliseconds;
        });
      }
    } on SocketException catch (e) {
      print('SocketException for ${config.server}:${config.port}: $e');
      if (mounted) {
        setState(() {
          _serverPings[config.id] = -1; // خطا در اتصال
        });
      }
    } on TimeoutException catch (_) {
      print('TimeoutException for ${config.server}:${config.port}');
      if (mounted) {
        setState(() {
          _serverPings[config.id] = -2; // Timeout
        });
      }
    } catch (e) {
      print('Error pinging ${config.server}:${config.port}: $e');
      if (mounted) {
        setState(() {
          _serverPings[config.id] = -3; // خطای عمومی
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPingingServer[config.id] = false;
        });
      }
    }
  }

  Color _getPingColor(int? ping) {
    if (ping == null) return Colors.grey; // در حال پینگ
    if (ping == -1 || ping == -3) return Colors.red; // خطا
    if (ping == -2) return Colors.orange; // Timeout
    if (ping < 100) return Colors.green;
    if (ping < 200) return Colors.lightGreen;
    if (ping < 300) return Colors.amber;
    return Colors.redAccent;
  }

  String _getPingText(int? ping) {
    if (ping == null) return 'در حال پینگ...';
    if (ping == -1) return 'خطا (اتصال)';
    if (ping == -2) return 'Timeout';
    if (ping == -3) return 'خطا';
    return '$ping ms';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('انتخاب سرور'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () {
              Navigator.pop(context, _selectedConfig);
            },
            tooltip: 'تایید انتخاب',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0E5EC), Color(0xFFF0F2F5)], // گرادیان پس‌زمینه روشن
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: widget.configs.isEmpty
            ? Center(
                child: Text(
                  'هیچ سروری در دسترس نیست.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: widget.configs.length,
                itemBuilder: (context, index) {
                  final config = widget.configs[index];
                  final bool isSelected = _selectedConfig?.id == config.id;
                  final int? serverPing = _serverPings[config.id];
                  final bool isPinging = _isPingingServer[config.id] ?? false;

                  return Card(
                    elevation: isSelected ? 10 : 5, // سایه بیشتر برای انتخاب شده
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: isSelected
                          ? BorderSide(color: Theme.of(context).colorScheme.secondary, width: 3)
                          : BorderSide.none,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: isSelected ? Theme.of(context).colorScheme.surface : Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      leading: Icon(
                        Icons.vpn_key_rounded,
                        color: isSelected ? Theme.of(context).colorScheme.secondary : Theme.of(context).primaryColor,
                        size: 30,
                      ),
                      title: Text(
                        config.remarks ?? 'نامشخص',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${config.server}:${config.port}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.network_check, size: 16, color: _getPingColor(serverPing)),
                              const SizedBox(width: 4),
                              if (isPinging)
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.secondary),
                                  ),
                                )
                              else
                                Text(
                                  'پینگ: ${_getPingText(serverPing)}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _getPingColor(serverPing)),
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
