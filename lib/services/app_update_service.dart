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

  static const String currentAppVersion = '1.0.1';

  AppUpdateInfo? _cachedUpdateInfo;
  AppUpdateInfo? get cachedUpdateInfo => _cachedUpdateInfo;

  /// Exposes version comparison for testing and validation
  bool isVersionGreater(String remote, String local) => _isVersionGreater(remote, local);

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
        Process.run('powershell', ['-NoProfile', '-Command', 'Start-Process', '"$url"']);
      } else if (!kIsWeb && Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (!kIsWeb && Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Failed to launch download URL: $e');
    }
  }

  /// Downloads and launches the update installer directly inside the app
  Future<void> downloadAndInstallUpdate({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    required void Function(String status) onStatus,
  }) async {
    try {
      onStatus('Connecting to update server...');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);

      // Prefer direct .exe download if url is .zip and .exe is available
      var targetUrl = downloadUrl;
      if (targetUrl.endsWith('.zip')) {
        targetUrl = targetUrl.replaceAll('.zip', '.exe');
      }

      var uri = Uri.parse(targetUrl);
      var req = await client.getUrl(uri);
      var resp = await req.close();

      // If .exe is not found, fallback to original URL (.zip)
      if (resp.statusCode != 200 && targetUrl != downloadUrl) {
        uri = Uri.parse(downloadUrl);
        req = await client.getUrl(uri);
        resp = await req.close();
      }

      if (resp.statusCode != 200) {
        throw Exception('Download failed with HTTP ${resp.statusCode}');
      }

      final contentLength = resp.contentLength;
      final tempDir = Directory.systemTemp;
      final isZip = uri.path.toLowerCase().endsWith('.zip');
      final fileName = isZip ? 'Slim4K-Setup.zip' : 'Slim4K-Setup.exe';
      final targetFile = File('${tempDir.path}/$fileName');

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      final sink = targetFile.openWrite();
      int received = 0;

      onStatus('Downloading Slim4K installer...');
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          final progress = (received / contentLength).clamp(0.0, 1.0);
          onProgress(progress, received, contentLength);
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      onStatus('Download complete! Preparing installer...');

      File installerToRun = targetFile;

      if (isZip && !kIsWeb && Platform.isWindows) {
        onStatus('Extracting installer package...');
        final extractDir = '${tempDir.path}\\Slim4K-Extracted-Update';
        final dir = Directory(extractDir);
        if (await dir.exists()) {
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        }
        await dir.create();

        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Expand-Archive -Path "${targetFile.path}" -DestinationPath "$extractDir" -Force'
        ]);

        final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.exe')).toList();
        if (files.isNotEmpty) {
          installerToRun = files.first;
        }
      }

      onStatus('Launching update installer...');
      await Future.delayed(const Duration(milliseconds: 600));

      if (!kIsWeb && Platform.isWindows) {
        // Launch Inno Setup installer detached, and close Slim4K to allow file overwrites
        await Process.start(
          installerToRun.path,
          [],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } else if (!kIsWeb && Platform.isMacOS) {
        await Process.run('open', [installerToRun.path]);
        exit(0);
      } else if (!kIsWeb && Platform.isLinux) {
        await Process.run('xdg-open', [installerToRun.path]);
        exit(0);
      }
    } catch (e) {
      debugPrint('Direct update installation failed: $e');
      rethrow;
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
