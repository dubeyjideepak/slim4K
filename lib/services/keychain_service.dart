import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure Keychain and Hardware Credential Storage
/// 
/// Persists critical device identifiers and quota tracking metrics so that
/// even if the app is uninstalled and reinstalled, the data is preserved
/// and cannot be reset by simply deleting local application cache files.
class KeychainService {
  static final KeychainService _instance = KeychainService._internal();
  factory KeychainService() => _instance;
  KeychainService._internal();

  static const String _serviceName = 'com.neertech.slim4k';
  
  // Storage Keys
  static const String keyClientId = 'slim4k_client_id';
  static const String keyBytesSlimmed = 'slim4k_bytes_slimmed';
  static const String keyBytesSaved = 'slim4k_bytes_saved';
  static const String keyFilesSlimmed = 'slim4k_files_slimmed';
  static const String keyQuotaLimitBytes = 'slim4k_quota_limit_bytes';
  static const String keyFirstSlimmedAt = 'slim4k_first_slimmed_at';
  static const String keyLastSlimmedAt = 'slim4k_last_slimmed_at';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      groupId: null,
      accountName: 'slim4k_secure',
      accessibility: KeychainAccessibility.unlocked,
    ),
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
    wOptions: WindowsOptions(
      useBackwardCompatibility: true,
    ),
  );

  /// Native macOS security CLI fallback (guarantees persistence across bundle re-installs on Mac)
  bool get _isMacDesktop => !kIsWeb && Platform.isMacOS;

  /// Native Windows Registry fallback (guarantees persistence across app folder deletion on Windows)
  bool get _isWindowsDesktop => !kIsWeb && Platform.isWindows;
  static const String _winRegKey = r'HKCU\Software\Neertech\Slim4K';

  /// Writes a key-value pair to Keychain / Secure Storage
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('FlutterSecureStorage write error for $key: $e');
    }

    if (_isMacDesktop) {
      await _writeNativeMacKeychain(key, value);
    } else if (_isWindowsDesktop) {
      await _writeWindowsRegistry(key, value);
    }
  }

  /// Reads a value from Keychain / Secure Storage
  Future<String?> read(String key) async {
    String? val;
    try {
      val = await _storage.read(key: key);
      if (val != null && val.isNotEmpty) return val;
    } catch (e) {
      debugPrint('FlutterSecureStorage read error for $key: $e');
    }

    if (_isMacDesktop) {
      val = await _readNativeMacKeychain(key);
      if (val != null && val.isNotEmpty) {
        // Repair standard storage if native keychain had it
        try {
          await _storage.write(key: key, value: val);
        } catch (_) {}
        return val;
      }
    } else if (_isWindowsDesktop) {
      val = await _readWindowsRegistry(key);
      if (val != null && val.isNotEmpty) {
        try {
          await _storage.write(key: key, value: val);
        } catch (_) {}
        return val;
      }
    }

    return null;
  }

  /// Deletes a key from Keychain / Secure Storage
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}

    if (_isMacDesktop) {
      await _deleteNativeMacKeychain(key);
    } else if (_isWindowsDesktop) {
      await _deleteWindowsRegistry(key);
    }
  }

  // --- Specialized Quota & Client ID Accessors ---

  Future<String?> getClientId() => read(keyClientId);
  Future<void> setClientId(String clientId) => write(keyClientId, clientId);

  Future<int?> getBytesSlimmed() async {
    final str = await read(keyBytesSlimmed);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> setBytesSlimmed(int bytes) => write(keyBytesSlimmed, bytes.toString());

  Future<int?> getBytesSaved() async {
    final str = await read(keyBytesSaved);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> setBytesSaved(int bytes) => write(keyBytesSaved, bytes.toString());

  Future<int?> getFilesSlimmed() async {
    final str = await read(keyFilesSlimmed);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> setFilesSlimmed(int count) => write(keyFilesSlimmed, count.toString());

  Future<int?> getQuotaLimitBytes() async {
    final str = await read(keyQuotaLimitBytes);
    return str != null ? int.tryParse(str) : null;
  }

  Future<void> setQuotaLimitBytes(int bytes) => write(keyQuotaLimitBytes, bytes.toString());

  Future<DateTime?> getFirstSlimmedAt() async {
    final str = await read(keyFirstSlimmedAt);
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> setFirstSlimmedAt(DateTime dt) => write(keyFirstSlimmedAt, dt.toIso8601String());

  Future<DateTime?> getLastSlimmedAt() async {
    final str = await read(keyLastSlimmedAt);
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> setLastSlimmedAt(DateTime dt) => write(keyLastSlimmedAt, dt.toIso8601String());

  // --- Native macOS /usr/bin/security CLI Integration ---

  Future<void> _writeNativeMacKeychain(String key, String value) async {
    try {
      // Use security command: add-generic-password with -U (update if exists)
      await Process.run(
        '/usr/bin/security',
        [
          'add-generic-password',
          '-a', key,
          '-s', _serviceName,
          '-w', value,
          '-U',
        ],
      );
    } catch (e) {
      debugPrint('Native Mac Keychain write error: $e');
    }
  }

  Future<String?> _readNativeMacKeychain(String key) async {
    try {
      final res = await Process.run(
        '/usr/bin/security',
        [
          'find-generic-password',
          '-a', key,
          '-s', _serviceName,
          '-w',
        ],
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (e) {
      debugPrint('Native Mac Keychain read error: $e');
    }
    return null;
  }

  Future<void> _deleteNativeMacKeychain(String key) async {
    try {
      await Process.run(
        '/usr/bin/security',
        [
          'delete-generic-password',
          '-a', key,
          '-s', _serviceName,
        ],
      );
    } catch (_) {}
  }

  // --- Native Windows Registry Fallback (HKCU\Software\Neertech\Slim4K) ---

  Future<void> _writeWindowsRegistry(String key, String value) async {
    try {
      await Process.run('reg', [
        'add',
        _winRegKey,
        '/v',
        key,
        '/t',
        'REG_SZ',
        '/d',
        value,
        '/f',
      ]);
    } catch (e) {
      debugPrint('Windows Registry write error: $e');
    }
  }

  Future<String?> _readWindowsRegistry(String key) async {
    try {
      final res = await Process.run('reg', [
        'query',
        _winRegKey,
        '/v',
        key,
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        final match = RegExp(RegExp.escape(key) + r'\s+REG_SZ\s+(.*)').firstMatch(out);
        if (match != null && match.group(1) != null) {
          final val = match.group(1)!.trim();
          if (val.isNotEmpty) return val;
        }
      }
    } catch (e) {
      debugPrint('Windows Registry read error: $e');
    }
    return null;
  }

  Future<void> _deleteWindowsRegistry(String key) async {
    try {
      await Process.run('reg', [
        'delete',
        _winRegKey,
        '/v',
        key,
        '/f',
      ]);
    } catch (_) {}
  }
}
