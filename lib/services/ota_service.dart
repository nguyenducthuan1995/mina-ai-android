import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String title;
  final String changelog;
  final String apkUrl;
  final bool forceUpdate;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.title,
    required this.changelog,
    required this.apkUrl,
    this.forceUpdate = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['version'] ?? json['tag_name'] ?? '2.0.1',
      versionCode: json['version_code'] ?? 3,
      title: json['title'] ?? 'Bản cập nhật mới',
      changelog: json['changelog'] ?? json['body'] ?? 'Cải thiện hiệu năng và sửa lỗi đàm thoại.',
      apkUrl: json['apk_url'] ?? '',
      forceUpdate: json['force_update'] ?? false,
    );
  }
}

class DownloadProgress {
  final int received;
  final int total;
  final double progress;

  DownloadProgress({
    required this.received,
    required this.total,
    required this.progress,
  });
}

class OtaService {
  OtaService._();
  static final OtaService instance = OtaService._();

  // Version đọc động từ package_info_plus — KHÔNG còn hardcode nữa
  // Điều này ngăn OTA loop: sau khi cài bản mới, app đọc đúng version mới
  String _currentVersion = '0.0.0';
  int _currentBuildNumber = 0;
  bool _versionLoaded = false;

  static const MethodChannel _channel = MethodChannel('com.lhht.ai_assistant/ota');

  // URL kiểm tra phiên bản (ưu tiên raw file trên GitHub, không bị rate-limit)
  static const String _versionUrl =
      'https://raw.githubusercontent.com/nguyenducthuan1995/mina-ai-android/main/version.json';
  static const String _githubLatestReleaseUrl =
      'https://api.github.com/repos/nguyenducthuan1995/mina-ai-android/releases/latest';

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  /// Đọc version thực tế từ APK đang cài (package_info_plus)
  Future<void> _loadCurrentVersion() async {
    if (_versionLoaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version; // e.g. "2.0.6"
      _currentBuildNumber = int.tryParse(info.buildNumber) ?? 0; // e.g. 8
      _versionLoaded = true;
      debugPrint('OTA: currentVersion=$_currentVersion build=$_currentBuildNumber');
    } catch (e) {
      debugPrint('OTA: Không đọc được package info: $e');
      // Fallback về version hardcode để không crash
      _currentVersion = '2.0.6';
      _currentBuildNumber = 8;
      _versionLoaded = true;
    }
  }

  /// So sánh hai chuỗi phiên bản dạng semver x.y.z
  /// Trả về 1 nếu v1 > v2, -1 nếu v1 < v2, 0 nếu bằng nhau
  int compareVersions(String v1, String v2) {
    final clean1 = v1.replaceAll(RegExp(r'^[vV]'), '').split('+')[0];
    final clean2 = v2.replaceAll(RegExp(r'^[vV]'), '').split('+')[0];

    final parts1 = clean1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = clean2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  /// Kiểm tra có bản cập nhật mới không
  Future<UpdateInfo?> checkUpdate() async {
    try {
      _isChecking = true;
      await _loadCurrentVersion(); // Đọc version thực từ APK

      // 1. Thử lấy từ version.json trên GitHub raw
      try {
        final res = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = json.decode(utf8.decode(res.bodyBytes));
          final info = UpdateInfo.fromJson(data);
          if (info.versionCode > _currentBuildNumber ||
              compareVersions(info.versionName, _currentVersion) > 0) {
            return info;
          }
          return null;
        }
      } catch (e) {
        debugPrint('Lỗi đọc version.json: $e');
      }

      // 2. Dự phòng: Thử lấy từ GitHub Releases API
      try {
        final res = await http
            .get(Uri.parse(_githubLatestReleaseUrl), headers: {'Accept': 'application/vnd.github.v3+json'})
            .timeout(const Duration(seconds: 5));

        if (res.statusCode == 200) {
          final data = json.decode(utf8.decode(res.bodyBytes));
          final tagName = data['tag_name'] as String? ?? '';
          final assets = (data['assets'] as List?) ?? [];
          String apkUrl = '';
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] ?? '';
              break;
            }
          }

          if (compareVersions(tagName, _currentVersion) > 0 && apkUrl.isNotEmpty) {
            return UpdateInfo(
              versionName: tagName,
              versionCode: _currentBuildNumber + 1,
              title: data['name'] ?? 'Bản cập nhật mới $tagName',
              changelog: data['body'] ?? 'Bản cập nhật mới từ hệ thống.',
              apkUrl: apkUrl,
            );
          }
        }
      } catch (e) {
        debugPrint('Lỗi đọc GitHub Releases: $e');
      }

      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// Kiểm tra cập nhật và hiển thị hộp thoại
  Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Đang kiểm tra phiên bản mới...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    final update = await checkUpdate();

    if (!context.mounted) return;

    if (update != null) {
      showUpdateDialog(context, update);
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text('Bạn đang sử dụng bản mới nhất (v$_currentVersion)'),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  /// Hiển thị hộp thoại thông báo cập nhật
  void showUpdateDialog(BuildContext context, UpdateInfo update) {
    showDialog(
      context: context,
      barrierDismissible: !update.forceUpdate,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Có bản cập nhật mới! 🚀',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phiên bản: ${update.versionName}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Nội dung cập nhật:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  update.changelog,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bản cập nhật sẽ được tải về và cài đặt trực tiếp trên màn hình xe.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          if (!update.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Để sau', style: TextStyle(color: Colors.grey)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Cập nhật ngay'),
            onPressed: () {
              Navigator.of(ctx).pop();
              downloadAndInstall(context, update);
            },
          ),
        ],
      ),
    );
  }

  /// Tải APK và mở màn hình cài đặt của Android
  Future<void> downloadAndInstall(BuildContext context, UpdateInfo update) async {
    final progressNotifier = ValueNotifier<DownloadProgress>(
      DownloadProgress(received: 0, total: 0, progress: 0.0),
    );
    bool isCancelled = false;

    // Hiển thị Dialog tiến trình tải sử dụng ValueNotifier
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_download_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 10),
            Text('Đang tải bản cập nhật...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: ValueListenableBuilder<DownloadProgress>(
          valueListenable: progressNotifier,
          builder: (context, data, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: data.total > 0 ? data.progress : null,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      data.total > 0
                          ? '${(data.received / (1024 * 1024)).toStringAsFixed(1)} MB / ${(data.total / (1024 * 1024)).toStringAsFixed(1)} MB'
                          : 'Đang kết nối tải về...',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      data.total > 0 ? '${(data.progress * 100).toStringAsFixed(0)}%' : '',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vui lòng giữ ứng dụng mở trong giây lát.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              isCancelled = true;
              Navigator.of(dialogCtx).pop();
            },
            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(update.apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Mã phản hồi: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final sanitizedVersion = update.versionName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final apkFile = File('${tempDir.path}/mina_update_$sanitizedVersion.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      int receivedBytes = 0;
      DateTime lastNotifyTime = DateTime.now();

      await for (final chunk in response.stream) {
        if (isCancelled) {
          await sink.close();
          if (await apkFile.exists()) await apkFile.delete();
          return;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastNotifyTime).inMilliseconds > 100 || receivedBytes == totalBytes) {
          lastNotifyTime = now;
          final p = totalBytes > 0 ? (receivedBytes / totalBytes) : 0.0;
          progressNotifier.value = DownloadProgress(
            received: receivedBytes,
            total: totalBytes,
            progress: p,
          );
        }
      }

      await sink.flush();
      await sink.close();

      // Đóng dialog tải
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Kích hoạt trình cài đặt Android qua MethodChannel
      final bool? success = await _channel.invokeMethod<bool>('installApk', {
        'filePath': apkFile.path,
      });

      if (success != true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể mở trình cài đặt APK. Vui lòng cấp quyền "Cài đặt ứng dụng không rõ nguồn gốc".'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải bản cập nhật: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
