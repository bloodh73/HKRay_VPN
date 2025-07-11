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
  late List<V2RayConfig> _configs; // Use a state variable for sorting
  final Map<String, int?> _serverPings = {};
  final Map<String, bool> _isPingingServer = {};
  bool _isSortingAndPinging = false; // To show a global loading indicator

  @override
  void initState() {
    super.initState();
    _selectedConfig = widget.currentSelectedConfig;
    _configs = List.from(widget.configs); // Initialize the state list

    for (var config in _configs) {
      _serverPings[config.id] = 0; // 0 means not tested yet
    }
  }

  /// Pings a single server and updates its status.
  Future<void> _realPingServer(V2RayConfig config) async {
    if (_isPingingServer[config.id] == true) return;

    setState(() {
      _isPingingServer[config.id] = true;
      _serverPings[config.id] = null; // Show loading
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

  /// Pings all servers, then sorts the list based on the results.
  Future<void> _pingAndSortServers() async {
    setState(() => _isSortingAndPinging = true);

    // Create a list of futures to ping all servers concurrently.
    final List<Future<void>> pingFutures = [];
    for (var config in _configs) {
      pingFutures.add(_realPingServer(config));
    }
    await Future.wait(pingFutures); // Wait for all pings to complete

    // Sort the list based on ping results
    _configs.sort((a, b) {
      final pingA = _serverPings[a.id] ?? 0;
      final pingB = _serverPings[b.id] ?? 0;

      final isAValid = pingA > 0;
      final isBValid = pingB > 0;

      if (isAValid && isBValid) {
        return pingA.compareTo(pingB); // Both valid, sort by ping
      } else if (isAValid) {
        return -1; // A is valid, B is not, so A comes first
      } else if (isBValid) {
        return 1; // B is valid, A is not, so B comes first
      } else {
        // Both are invalid (error or untested), sort errors to the bottom
        // A higher negative number (e.g., -1) is "better" than a lower one (-2)
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
    if (ping == null || ping == 0) return Colors.grey;
    if (ping < 0) return Colors.red;
    if (ping < 1800) return Colors.green;
    if (ping < 1900) return Colors.orange;
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
        // Removed the sort button from the AppBar
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.blue.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              // Added Column to hold the button and the list
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
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 5,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // Expanded to make the ListView take available space
                  child: _configs.isEmpty
                      ? Center(
                          child: Text(
                            'هیچ سروری برای نمایش وجود ندارد.',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade700,
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
                                      : Colors.blueGrey,
                                  size: 30,
                                ),
                                title: Text(
                                  config.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.blueAccent.shade700
                                            : Colors.black87,
                                      ),
                                ),
                                subtitle: Text(
                                  '${config.protocol?.toUpperCase() ?? 'نامشخص'} - ${config.server}:${config.port}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.grey.shade600),
                                ),
                                trailing: SizedBox(
                                  width: 100,
                                  child: isPinging
                                      ? const Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
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
                                  setState(() => _selectedConfig = config);
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
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("در حال تست و مرتب‌سازی سرورها..."),
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
