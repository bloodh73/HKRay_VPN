// v2ray_config.dart
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'dart:convert';

class V2RayConfig {
  final String id;
  final String name; // نام قابل نمایش سرور (remarks)
  final String server; // آدرس سرور
  final int port; // پورت سرور
  final String? protocol; // پروتکل (vmess, vless, shadowsocks, trojan)
  final String? remarks; // توضیحات سرور (همان name)
  final String fullConfigJson; // پیکربندی کامل JSON برای V2Ray

  V2RayConfig({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    this.protocol,
    this.remarks,
    required this.fullConfigJson,
  });

  // Factory constructor برای ساخت V2RayConfig از V2RayURL
  factory V2RayConfig.fromV2RayURL(V2RayURL v2rayUrl) {
    String? extractedProtocol;
    String fullConfig = v2rayUrl.getFullConfiguration();
    print(
      'V2RayConfig.fromV2RayURL - Full config JSON from V2RayURL: $fullConfig',
    );

    try {
      final configMap = jsonDecode(fullConfig);
      print('V2RayConfig.fromV2RayURL - Decoded config map: $configMap');

      // تلاش برای استخراج پروتکل از فیلد 'protocol' در اولین outbound
      if (configMap.containsKey('outbounds') &&
          configMap['outbounds'] is List &&
          configMap['outbounds'].isNotEmpty) {
        final outbound = configMap['outbounds'][0];
        if (outbound.containsKey('protocol')) {
          extractedProtocol = outbound['protocol'] as String;
          print(
            'V2RayConfig.fromV2RayURL - Protocol extracted from outbounds: $extractedProtocol',
          );
        }
      }

      // اگر پروتکل در outbounds پیدا نشد، سعی کنید از طرح URI استخراج کنید
      if (extractedProtocol == null || extractedProtocol.isEmpty) {
        final uriScheme = v2rayUrl.url.split('://').first.toLowerCase();
        print(
          'V2RayConfig.fromV2RayURL - Protocol extracted from URI scheme: $uriScheme',
        );
        switch (uriScheme) {
          case 'vmess':
            extractedProtocol = 'vmess';
            break;
          case 'vless':
            extractedProtocol = 'vless';
            break;
          case 'trojan':
            extractedProtocol = 'trojan';
            break;
          case 'ss': // Shadowsocks
            extractedProtocol = 'shadowsocks';
            break;
          // پروتکل های دیگر را در صورت نیاز اضافه کنید
        }
      }
    } catch (e) {
      print('Error parsing V2RayURL config for protocol: $e');
      // در صورت بروز خطا، extractedProtocol را null نگه دارید
    }
    print(
      'V2RayConfig.fromV2RayURL - Final extracted protocol: $extractedProtocol',
    );

    // اطمینان از اینکه name و remarks هرگز خالی نباشند
    final String effectiveRemark = v2rayUrl.remark.isNotEmpty
        ? v2rayUrl.remark
        : '${extractedProtocol?.toUpperCase() ?? 'Unknown'} - ${v2rayUrl.address}:${v2rayUrl.port}';

    return V2RayConfig(
      // ساخت یک id منحصر به فرد از ترکیب آدرس و پورت
      id: '${v2rayUrl.address}:${v2rayUrl.port}',
      name: effectiveRemark, // استفاده از نام موثر
      server: v2rayUrl.address,
      port: v2rayUrl.port,
      protocol: extractedProtocol, // پروتکل استخراج شده را اختصاص دهید
      remarks: effectiveRemark, // استفاده از نام موثر برای remarks
      fullConfigJson: fullConfig, // استفاده از fullConfig که قبلاً استخراج شده
    );
  }

  // Factory constructor برای ساخت V2RayConfig از JSON (برای ذخیره/بازیابی)
  factory V2RayConfig.fromJson(Map<String, dynamic> json) {
    return V2RayConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      server: json['server'] ?? '',
      port: json['port'] ?? 0,
      protocol: json['protocol'],
      remarks: json['remarks'],
      fullConfigJson: json['fullConfigJson'] ?? '{}',
    );
  }

  // تبدیل V2RayConfig به JSON برای ذخیره سازی
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'server': server,
      'port': port,
      'protocol': protocol,
      'remarks': remarks,
      'fullConfigJson': fullConfigJson,
    };
  }
}

class V2RaySubscription {
  final String id;
  final String name;
  final String url;
  final DateTime? lastUpdate;
  final List<V2RayConfig> configs;

  V2RaySubscription({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdate,
    List<V2RayConfig>? configs,
  }) : configs = configs ?? [];

  factory V2RaySubscription.fromJson(Map<String, dynamic> json) {
    return V2RaySubscription(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'])
          : null,
      configs: json['configs'] != null
          ? (json['configs'] as List)
                .map((i) => V2RayConfig.fromJson(i))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'lastUpdate': lastUpdate?.toIso8601String(),
      'configs': configs.map((e) => e.toJson()).toList(),
    };
  }
}
