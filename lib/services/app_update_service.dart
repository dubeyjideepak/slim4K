import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'quota_service.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool isUpdateAvailable;
  final bool isMandatory;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isUpdateAvailable,
    this.isMandatory = false,
  });
}

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  static const String currentAppVersion = '1.0.0';

  AppUpdateInfo? _cachedUpdateInfo;
  AppUpdateInfo? get cachedUpdateInfo => _cachedUpdateInfo;

  /// Checks Firestore global_pricing for new releases
  Future<AppUpdateInfo?> checkForUpdates() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/global_pricing?key=${QuotaService.apiKey}',
      );

      final req = await client.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode == 200) {
        final body = await utf8.decoder.bind(resp).join();
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final latestVersion = fields['latest_version']?['stringValue'] ?? currentAppVersion;
        final downloadUrl = fields['download_url']?['stringValue'] ?? 'https://neertechtechnologies.in/downloads/Slim4K-Windows-Setup.zip';
        final releaseNotes = fields['release_notes']?['stringValue'] ?? 'Performance optimizations and stability improvements.';
        final minVersion = fields['min_supported_version']?['stringValue'] ?? '1.0.0';

        final hasUpdate = _isVersionGreater(latestVersion, currentAppVersion);
        final isMandatory = _isVersionGreater(minVersion, currentAppVersion);

        _cachedUpdateInfo = AppUpdateInfo(
          currentVersion: currentAppVersion,
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          isUpdateAvailable: hasUpdate,
          isMandatory: isMandatory,
        );

        client.close();
        return _cachedUpdateInfo;
      }
      client.close();
    } catch (e) {
      debugPrint('Update check error: $e');
    }
    return null;
  }

  /// Launch update download in browser
  void launchUpdateDownload(String url) {
    try {
      if (!kIsWeb && Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (!kIsWeb && Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (!kIsWeb && Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Failed to launch download URL: $e');
    }
  }

  /// Compares semantic version strings e.g. "1.0.1" > "1.0.0"
  bool _isVersionGreater(String remote, String local) {
    try {
      final rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final lParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;
      for (int i = 0; i < maxLen; i++) {
        final rVal = i < rParts.length ? rParts[i] : 0;
        final lVal = i < lParts.length ? lParts[i] : 0;
        if (rVal > lVal) return true;
        if (rVal < lVal) return false;
      }
    } catch (_) {}
    return false;
  }
}
