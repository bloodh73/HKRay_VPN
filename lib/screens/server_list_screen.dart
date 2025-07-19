import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/v2ray_config.dart';
import '../services/v2ray_service.dart';
import 'dart:async';

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
  late List<V2RayConfig> _configs;
  final Map<String, int?> _serverPings = {};
  final Map<String, bool> _isPingingServer = {};
  bool _isSortingAndPinging = false;

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.currentSelectedConfig;
    _configs = List.from(widget.configs);

    for (var config in _configs) {
      _serverPings[config.id] = 0;
    }
  }

  Future<void> _realPingServer(V2RayConfig config) async {
    if (_isPingingServer[config.id] == true) return;

    setState(() {
      _isPingingServer[config.id] = true;
      _serverPings[config.id] = null;
    });

    try {
      final v2rayService = Provider.of<V2RayService>(context, listen: false);
      final int pingResult = await v2rayService.getRealPing(config);
      if (mounted) {
        setState(() => _serverPings[config.id] = pingResult);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _serverPings[config.id] = -1);
      }
    } finally {
      if (mounted) {
        setState(() => _isPingingServer[config.id] = false);
      }
    }
  }

  Future<void> _pingAndSortServers() async {
    setState(() => _isSortingAndPinging = true);

    final List<Future<void>> pingFutures = [];
    for (var config in _configs) {
      pingFutures.add(_realPingServer(config));
    }
    await Future.wait(pingFutures);

    _configs.sort((a, b) {
      final pingA = _serverPings[a.id] ?? 0;
      final pingB = _serverPings[b.id] ?? 0;

      final isAValid = pingA > 0;
      final isBValid = pingB > 0;

      if (isAValid && isBValid) {
        return pingA.compareTo(pingB);
      } else if (isAValid) {
        return -1;
      } else if (isBValid) {
        return 1;
      } else {
        return pingB.compareTo(pingA);
      }
    });

    setState(() => _isSortingAndPinging = false);
  }

  String _getPingText(int? ping) {
    if (ping == null) return '...';
    if (ping == 0) return 'تست';
    if (ping < 0) return 'خطا';
    return '$ping ms';
  }

  Color _getPingColor(int? ping) {
    if (ping == null || ping == 0) {
      return Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    }
    if (ping < 0) return Theme.of(context).colorScheme.error;
    if (ping < 1800) return Colors.green; // Specific color for good ping
    if (ping < 1900) return Colors.orange; // Specific color for moderate ping
    return Colors.red; // Specific color for bad ping
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'انتخاب سرور',
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
        centerTitle: true,
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
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).appBarTheme.foregroundColor,
          ),
          onPressed: () {
            Navigator.pop(context, _selectedConfig);
          },
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.07,
                    width: MediaQuery.of(context).size.height,
                    child: ElevatedButton.icon(
                      onPressed: _isSortingAndPinging
                          ? null
                          : _pingAndSortServers,
                      icon: const Icon(Icons.sort, size: 24),
                      label: Text(
                        _isSortingAndPinging
                            ? 'در حال تست و مرتب‌سازی...'
                            : 'تست و مرتب‌سازی سرورها',
                        // FIX: Resolve the MaterialStateProperty<TextStyle?> to TextStyle?
                        style: Theme.of(context)
                            .elevatedButtonTheme
                            .style
                            ?.textStyle
                            ?.resolve(WidgetState.values.toSet()),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondary, // Using secondary for sort button
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSecondary,
                        elevation: 5,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _configs.isEmpty
                      ? Center(
                          child: Text(
                            'هیچ سروری برای نمایش وجود ندارد.',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _configs.length,
                          itemBuilder: (context, index) {
                            final config = _configs[index];
                            final isSelected = _selectedConfig?.id == config.id;
                            final serverPing = _serverPings[config.id];
                            final isPinging =
                                _isPingingServer[config.id] == true;

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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.secondary,
                                        width: 2.5,
                                      )
                                    : BorderSide.none,
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                leading: Icon(
                                  Icons.vpn_lock,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.secondary
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                  size: 30,
                                ),
                                title: Text(
                                  config.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).textTheme.titleMedium?.color,
                                      ),
                                ),
                                subtitle: Text(
                                  '${config.protocol?.toUpperCase() ?? 'نامشخص'} - ${config.server}:${config.port}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                ),
                                trailing: SizedBox(
                                  width: 100,
                                  child: isPinging
                                      ? Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  ),
                                            ),
                                          ),
                                        )
                                      : TextButton.icon(
                                          onPressed: () =>
                                              _realPingServer(config),
                                          icon: Icon(
                                            Icons.network_ping,
                                            size: 20,
                                            color: _getPingColor(serverPing),
                                          ),
                                          label: Text(
                                            _getPingText(serverPing),
                                            style: TextStyle(
                                              color: _getPingColor(serverPing),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                ),
                                onTap: () {
                                  Navigator.pop(context, config);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (_isSortingAndPinging)
            Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              child: Center(
                child: Card(
                  color: Theme.of(context).cardTheme.color,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          "در حال تست و مرتب‌سازی سرورها...",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
