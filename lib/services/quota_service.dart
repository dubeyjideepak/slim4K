import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';
import 'keychain_service.dart';

/// Service managing the 10 TB Annual Video Slimming Quota and Usage Tracking
///
/// Features:
/// 1. Dual persistence: Keychain (hardware secure storage) + Firestore (cloud sync).
/// 2. Re-install resilient: Even if the application is deleted and reinstalled,
///    the client ID, quota limit, and total TBs slimmed are immediately restored
///    from the hardware Keychain and Firestore.
/// 3. Tamper-resistant reconciliation: Always enforces `max(keychain, local, cloud)`
///    so that rolling back local files or deleting directories cannot reset the quota counter.
class QuotaService extends ChangeNotifier {
  static final QuotaService _instance = QuotaService._internal();
  factory QuotaService() => _instance;
  QuotaService._internal();

  final KeychainService _keychain = KeychainService();

  static const String projectId = 'appactivations-f47d0';
  static const String apiKey = 'AIzaSyBp4GOH_XBhYgqNbRW9RpeIjUhFX7soWA4';
  static const String appId = 'slim4k';

  /// Standard 10 TB Annual Limit (10 TiB = 10 * 1024^4 bytes)
  static const int defaultQuotaBytes = 10 * 1024 * 1024 * 1024 * 1024; // 10,995,116,277,760
  static const double defaultQuotaTb = 10.0;

  /// 2.0 GB Free Trial Limit for unactivated users (default displayed quota)
  static const int trialLimitBytes = 2 * 1024 * 1024 * 1024; // 2,147,483,648
  static const double defaultTrialLimitGb = 2.0;

  /// 2.5 GB Hard Processing Ceiling during active file slimming
  static const int trialHardLimitBytes = 2684354560; // 2.5 * 1024 * 1024 * 1024
  static const double defaultTrialHardLimitGb = 2.5;

  int _trialLimitBytes = trialLimitBytes;
  int _totalBytesSlimmed = 0;
  int _totalBytesSaved = 0;
  int _totalFilesSlimmed = 0;
  int _quotaLimitBytes = defaultQuotaBytes;
  DateTime? _firstSlimmedAt;
  DateTime? _lastSlimmedAt;
  bool _isInitialized = false;
  bool _isSyncing = false;

  bool _isLicenseActivated = false;
  String? _licenseKey;
  DateTime? _licenseExpiresAt;

  List<String> _activeSeats = [];
  List<String> get activeSeats => _activeSeats;
  int _maxSeats = 2;
  int get maxSeats => _maxSeats;
  bool _isSeatLimitReached = false;
  bool get isSeatLimitReached => _isSeatLimitReached;
  String? _accountInvoiceId;
  String? get accountInvoiceId => _accountInvoiceId;

  // Getters
  int get totalBytesSlimmed => _totalBytesSlimmed;
  int get totalBytesSaved => _totalBytesSaved;
  int get totalFilesSlimmed => _totalFilesSlimmed;
  int get quotaLimitBytes => _quotaLimitBytes;
  int get currentTrialLimitBytes => _trialLimitBytes;
  DateTime? get firstSlimmedAt => _firstSlimmedAt;
  DateTime? get lastSlimmedAt => _lastSlimmedAt;
  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;

  bool get isLicenseActivated => _isLicenseActivated;
  bool get isTrialMode => !_isLicenseActivated;
  bool get isTrialExceeded => isTrialMode && (_totalBytesSlimmed >= _trialLimitBytes);

  /// Checks if trial processing has surpassed the 2.5 GB hard live processing ceiling
  bool isHardLimitExceeded({int additionalBytes = 0}) {
    if (!isTrialMode) return false;
    return (_totalBytesSlimmed + additionalBytes) >= trialHardLimitBytes;
  }
  bool get isLicenseExpired => _isLicenseActivated && _licenseExpiresAt != null && DateTime.now().isAfter(_licenseExpiresAt!);
  String? get licenseKey => _licenseKey;
  DateTime? get licenseExpiresAt => _licenseExpiresAt;

  double get trialLimitGb => _trialLimitBytes / (1024.0 * 1024.0 * 1024.0);
  double get trialUsedGb => _totalBytesSlimmed / (1024.0 * 1024.0 * 1024.0);
  double get trialRemainingGb => max(0.0, trialLimitGb - trialUsedGb);

  // Calculated Metric Getters
  double get totalTbSlimmed => _totalBytesSlimmed / 1099511627776.0;
  double get totalTbSaved => _totalBytesSaved / 1099511627776.0;
  double get quotaLimitTb => _quotaLimitBytes / 1099511627776.0;
  double get remainingTb => max(0.0, quotaLimitTb - totalTbSlimmed);
  int get remainingBytes => max(0, _quotaLimitBytes - _totalBytesSlimmed);

  /// Percentage of quota consumed (0.0 to 100.0)
  double get usedPercentage {
    if (isTrialMode) {
      return (_totalBytesSlimmed / _trialLimitBytes * 100.0).clamp(0.0, 100.0);
    }
    if (_quotaLimitBytes <= 0) return 0.0;
    return (_totalBytesSlimmed / _quotaLimitBytes * 100.0).clamp(0.0, 100.0);
  }

  /// Whether the quota has been reached (2 GB trial limit or 10 TB annual limit or expired)
  bool get isQuotaExceeded => isTrialExceeded || isLicenseExpired || (_isLicenseActivated && _totalBytesSlimmed >= _quotaLimitBytes);

  /// Formatted strings for display
  String get formattedUsage => isTrialMode
      ? '${trialUsedGb.toStringAsFixed(2)} GB / ${trialLimitGb.toStringAsFixed(1)} GB (Trial)'
      : '${totalTbSlimmed.toStringAsFixed(2)} TB / ${quotaLimitTb.toStringAsFixed(1)} TB';

  String get formattedRemaining => isTrialMode
      ? '${trialRemainingGb.toStringAsFixed(2)} GB Trial remaining'
      : '${remainingTb.toStringAsFixed(2)} TB remaining';

  String get formattedPercentage => '${usedPercentage.toStringAsFixed(1)}%';

  Future<File> _getLocalCacheFile() async {
    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (_) {
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }
    }
    return File(p.join(dir.path, 'slim4k_quota_tracker.json'));
  }

  /// Initializes quota metrics by checking Keychain, local file cache, and Firestore
  Future<void> initialize({required String clientId}) async {
    // 1. Read from Keychain
    final kcBytes = await _keychain.getBytesSlimmed() ?? 0;
    final kcSaved = await _keychain.getBytesSaved() ?? 0;
    final kcFiles = await _keychain.getFilesSlimmed() ?? 0;
    final kcQuota = await _keychain.getQuotaLimitBytes() ?? defaultQuotaBytes;
    final kcFirst = await _keychain.getFirstSlimmedAt();
    final kcLast = await _keychain.getLastSlimmedAt();

    // 2. Read from local cache file
    int localBytes = 0;
    int localSaved = 0;
    int localFiles = 0;
    int localQuota = defaultQuotaBytes;
    DateTime? localFirst;
    DateTime? localLast;

    try {
      final file = await _getLocalCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        localBytes = json['bytes_slimmed'] as int? ?? 0;
        localSaved = json['bytes_saved'] as int? ?? 0;
        localFiles = json['files_count'] as int? ?? 0;
        localQuota = json['quota_limit_bytes'] as int? ?? defaultQuotaBytes;
        if (json['first_slimmed_at'] != null) {
          localFirst = DateTime.tryParse(json['first_slimmed_at'].toString());
        }
        if (json['last_slimmed_at'] != null) {
          localLast = DateTime.tryParse(json['last_slimmed_at'].toString());
        }
      }
    } catch (e) {
      debugPrint('Error reading local quota cache: $e');
    }

    // Best local/keychain values (enforce maximum)
    _totalBytesSlimmed = max(kcBytes, localBytes);
    _totalBytesSaved = max(kcSaved, localSaved);
    _totalFilesSlimmed = max(kcFiles, localFiles);
    _quotaLimitBytes = max(kcQuota, localQuota);
    _firstSlimmedAt = kcFirst ?? localFirst;
    _lastSlimmedAt = kcLast ?? localLast;

    // Load license state
    final kcActivated = await _keychain.isLicenseActivated();
    final kcKey = await _keychain.getLicenseKey();
    final kcExpires = await _keychain.getLicenseExpiresAt();
    _isLicenseActivated = kcActivated;
    _licenseKey = kcKey;
    _licenseExpiresAt = kcExpires;

    _isInitialized = true;
    notifyListeners();

    // 3. Online sync with Firestore
    await syncWithFirestore(clientId: clientId);
  }

  /// Activates a verified license key and unlocks 10 TB annual quota
  Future<void> activateLicense({
    required String licenseKey,
    int validityDays = 365,
    int? quotaBytes,
  }) async {
    _isLicenseActivated = true;
    _licenseKey = licenseKey;
    _licenseExpiresAt = DateTime.now().add(Duration(days: validityDays));
    if (quotaBytes != null && quotaBytes > 0) {
      _quotaLimitBytes = quotaBytes;
    }
    await _keychain.setLicenseActivated(true);
    await _keychain.setLicenseKey(licenseKey);
    await _keychain.setLicenseExpiresAt(_licenseExpiresAt!);
    if (quotaBytes != null && quotaBytes > 0) {
      await _keychain.setQuotaLimitBytes(quotaBytes);
    }
    await _saveLocalCache();
    notifyListeners();
  }

  /// Directly redeems a standalone License Key (e.g. LIC-...) from receipt or invoice
  Future<bool> redeemLicenseKey({
    required String licenseKey,
    required String clientId,
  }) async {
    final cleanKey = licenseKey.trim().toUpperCase();
    if (cleanKey.isEmpty) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/lic_$cleanKey?key=$apiKey',
      );
      final req = await client.getUrl(uri);
      final resp = await req.close();

      if (resp.statusCode == 200) {
        final body = await utf8.decoder.bind(resp).join();
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final isActive = fields['is_active']?['booleanValue'] != false;
        if (!isActive) {
          client.close();
          return false;
        }

        final quotaBytes = int.tryParse(fields['quota_limit_bytes']?['integerValue']?.toString() ?? '') ?? defaultQuotaBytes;
        final validityDays = int.tryParse(fields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;

        await activateLicense(
          licenseKey: cleanKey,
          validityDays: validityDays,
          quotaBytes: quotaBytes,
        );

        if (clientId.isNotEmpty) {
          await _patchQuotaToFirestore(client, clientId);
        }

        client.close();
        return true;
      }
      client.close();
    } catch (e) {
      debugPrint('License redemption error: $e');
    }
    return false;
  }

  /// Records a successfully slimmed video
  Future<void> recordSlimmedVideo({
    required int inputBytes,
    required int outputBytes,
    required String clientId,
  }) async {
    if (inputBytes <= 0) return;

    final now = DateTime.now();
    _totalBytesSlimmed += inputBytes;
    final saved = inputBytes - outputBytes;
    if (saved > 0) {
      _totalBytesSaved += saved;
    }
    _totalFilesSlimmed += 1;
    _firstSlimmedAt ??= now;
    _lastSlimmedAt = now;

    notifyListeners();

    // 1. Immediately save to Keychain
    await _keychain.setBytesSlimmed(_totalBytesSlimmed);
    await _keychain.setBytesSaved(_totalBytesSaved);
    await _keychain.setFilesSlimmed(_totalFilesSlimmed);
    await _keychain.setLastSlimmedAt(now);
    if (_firstSlimmedAt != null) {
      await _keychain.setFirstSlimmedAt(_firstSlimmedAt!);
    }

    // 2. Save to local cache file
    await _saveLocalCache();

    // 3. Sync to Firestore in background (if online)
    _syncToFirestoreBackground(clientId);
  }

  Future<void> _saveLocalCache() async {
    try {
      final file = await _getLocalCacheFile();
      await file.parent.create(recursive: true);
      final data = {
        'bytes_slimmed': _totalBytesSlimmed,
        'bytes_saved': _totalBytesSaved,
        'files_count': _totalFilesSlimmed,
        'quota_limit_bytes': _quotaLimitBytes,
        'is_license_activated': _isLicenseActivated,
        'license_key': _licenseKey,
        'license_expires_at': _licenseExpiresAt?.toIso8601String(),
        'first_slimmed_at': _firstSlimmedAt?.toIso8601String(),
        'last_slimmed_at': _lastSlimmedAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving local quota cache: $e');
    }
  }

  void _syncToFirestoreBackground(String clientId) {
    Future.microtask(() async {
      try {
        if (clientId.isNotEmpty) {
          await syncWithFirestore(clientId: clientId);
        }
        final user = AuthService().currentUser;
        if (user != null && user.isValid) {
          await syncWithGoogleAccount(user: user, clientId: clientId);
        }
      } catch (e) {
        debugPrint('Background quota sync notice: $e');
      }
    });
  }

  /// Bidirectional sync with Firestore
  Future<void> syncWithFirestore({required String clientId}) async {
    if (clientId.isEmpty) return;
    _isSyncing = true;

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/$clientId?key=$apiKey',
      );

      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      if (resp.statusCode == 200) {
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        // Parse Firestore values
        int remoteBytes = 0;
        final rb = fields['bytes_slimmed'];
        if (rb != null) {
          remoteBytes = int.tryParse(rb['integerValue']?.toString() ?? '') ??
              (rb['doubleValue'] as num?)?.toInt() ?? 0;
        }

        int remoteSaved = 0;
        final rs = fields['bytes_saved'];
        if (rs != null) {
          remoteSaved = int.tryParse(rs['integerValue']?.toString() ?? '') ??
              (rs['doubleValue'] as num?)?.toInt() ?? 0;
        }

        int remoteFiles = 0;
        final rf = fields['files_count'];
        if (rf != null) {
          remoteFiles = int.tryParse(rf['integerValue']?.toString() ?? '') ?? 0;
        }

        int remoteQuota = defaultQuotaBytes;
        final rq = fields['quota_limit_bytes'];
        if (rq != null) {
          remoteQuota = int.tryParse(rq['integerValue']?.toString() ?? '') ?? defaultQuotaBytes;
        }

        // Reconcile with maximum (prevents tampering or reset by reinstall)
        final reconciledBytes = max(_totalBytesSlimmed, remoteBytes);
        final reconciledSaved = max(_totalBytesSaved, remoteSaved);
        final reconciledFiles = max(_totalFilesSlimmed, remoteFiles);
        final reconciledQuota = max(_quotaLimitBytes, remoteQuota);

        final changedLocally = reconciledBytes > _totalBytesSlimmed ||
            reconciledSaved > _totalBytesSaved ||
            reconciledFiles > _totalFilesSlimmed;

        final changedRemotely = reconciledBytes > remoteBytes ||
            reconciledSaved > remoteSaved ||
            reconciledFiles > remoteFiles;

        _totalBytesSlimmed = reconciledBytes;
        _totalBytesSaved = reconciledSaved;
        _totalFilesSlimmed = reconciledFiles;
        _quotaLimitBytes = reconciledQuota;

        // Persist reconciled values to Keychain and local file
        await _keychain.setBytesSlimmed(_totalBytesSlimmed);
        await _keychain.setBytesSaved(_totalBytesSaved);
        await _keychain.setFilesSlimmed(_totalFilesSlimmed);
        await _keychain.setQuotaLimitBytes(_quotaLimitBytes);
        await _saveLocalCache();

        // Reconcile trial limit if overridden from Firestore
        final remoteTrial = fields['trial_limit_bytes'];
        if (remoteTrial != null) {
          final parsedTrial = int.tryParse(remoteTrial['integerValue']?.toString() ?? '');
          if (parsedTrial != null && parsedTrial > 0) {
            _trialLimitBytes = parsedTrial;
          }
        }

        // Reconcile license activation status from Firestore
        final remoteLicenseActivated = fields['is_license_activated']?['booleanValue'] == true;
        final remotePaymentStatus = fields['payment_status']?['stringValue']?.toUpperCase();
        if (remoteLicenseActivated || remotePaymentStatus == 'PAID' || remotePaymentStatus == 'SUCCESS') {
          if (!_isLicenseActivated) {
            final validityDays = int.tryParse(fields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;
            final internalLicenseId = fields['internal_license_id']?['stringValue'] ?? 'AUTO-$clientId';
            await activateLicense(
              licenseKey: internalLicenseId,
              validityDays: validityDays,
              quotaBytes: reconciledQuota,
            );
          }
        }

        // Push update to Firestore if local had higher counts
        if (changedRemotely || remoteBytes == 0) {
          await _patchQuotaToFirestore(client, clientId);
        }

        if (changedLocally) {
          notifyListeners();
        }
      }

      client.close();
    } catch (e) {
      debugPrint('Quota Firestore sync offline/skipped: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _patchQuotaToFirestore(HttpClient client, String clientId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'fields': {
        'bytes_slimmed': {'integerValue': _totalBytesSlimmed.toString()},
        'tb_slimmed': {'doubleValue': double.parse(totalTbSlimmed.toStringAsFixed(4))},
        'bytes_saved': {'integerValue': _totalBytesSaved.toString()},
        'files_count': {'integerValue': _totalFilesSlimmed.toString()},
        'quota_limit_bytes': {'integerValue': _quotaLimitBytes.toString()},
        'quota_limit_tb': {'doubleValue': double.parse(quotaLimitTb.toStringAsFixed(1))},
        'last_slimmed_at': {'stringValue': _lastSlimmedAt?.toIso8601String() ?? nowIso},
      }
    };

    final fieldsQuery = 'updateMask.fieldPaths=bytes_slimmed'
        '&updateMask.fieldPaths=tb_slimmed'
        '&updateMask.fieldPaths=bytes_saved'
        '&updateMask.fieldPaths=files_count'
        '&updateMask.fieldPaths=quota_limit_bytes'
        '&updateMask.fieldPaths=quota_limit_tb'
        '&updateMask.fieldPaths=last_slimmed_at';

    // 1. Update /apps/slim4k/clients/{clientId}
    final uri1 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/$clientId?$fieldsQuery&key=$apiKey',
    );
    final req1 = await client.patchUrl(uri1);
    req1.headers.contentType = ContentType.json;
    req1.write(jsonEncode(payload));
    final resp1 = await req1.close();
    await resp1.drain();

    // 2. Also update mirror /app_activations/{appId}_{clientId}
    final uri2 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/app_activations/${appId}_$clientId?$fieldsQuery&key=$apiKey',
    );
    final req2 = await client.patchUrl(uri2);
    req2.headers.contentType = ContentType.json;
    req2.write(jsonEncode(payload));
    final resp2 = await req2.close();
    await resp2.drain();
  }

  /// Synchronizes cumulative quota and active license with the user's Google Account in Firestore
  Future<void> syncWithGoogleAccount({required UserProfile user, required String clientId}) async {
    final emailDocId = AuthService.emailToDocId(user.email);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final uri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/user_$emailDocId?key=$apiKey',
      );

      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();

      if (resp.statusCode == 200) {
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final remoteBytes = int.tryParse(fields['bytes_slimmed']?['integerValue']?.toString() ?? '') ?? 0;
        final remoteSaved = int.tryParse(fields['bytes_saved']?['integerValue']?.toString() ?? '') ?? 0;
        final remoteFiles = int.tryParse(fields['files_count']?['integerValue']?.toString() ?? '') ?? 0;
        final remoteQuota = int.tryParse(fields['quota_limit_bytes']?['integerValue']?.toString() ?? '') ?? _quotaLimitBytes;

        final reconciledBytes = max(_totalBytesSlimmed, remoteBytes);
        final reconciledSaved = max(_totalBytesSaved, remoteSaved);
        final reconciledFiles = max(_totalFilesSlimmed, remoteFiles);
        final reconciledQuota = max(_quotaLimitBytes, remoteQuota);

        _totalBytesSlimmed = reconciledBytes;
        _totalBytesSaved = reconciledSaved;
        _totalFilesSlimmed = reconciledFiles;
        _quotaLimitBytes = reconciledQuota;

        await _keychain.setBytesSlimmed(_totalBytesSlimmed);
        await _keychain.setBytesSaved(_totalBytesSaved);
        await _keychain.setFilesSlimmed(_totalFilesSlimmed);
        await _keychain.setQuotaLimitBytes(_quotaLimitBytes);
        await _saveLocalCache();

        // Check 2-device seat allocation limit
        final rawDevices = fields['active_devices']?['arrayValue']?['values'] as List<dynamic>?;
        _activeSeats = rawDevices != null
            ? rawDevices.map((v) => v['stringValue']?.toString() ?? '').where((s) => s.isNotEmpty).toList()
            : <String>[];
        _maxSeats = int.tryParse(fields['max_active_devices']?['integerValue']?.toString() ?? '') ?? 2;
        _accountInvoiceId = fields['invoice_id']?['stringValue'];

        final isDeviceRegistered = clientId.isNotEmpty && _activeSeats.contains(clientId);
        _isSeatLimitReached = !isDeviceRegistered && _activeSeats.length >= _maxSeats;

        // Check if account has an active commercial license purchased on another machine
        final isLicenseActive = fields['is_license_activated']?['booleanValue'] == true;
        final paymentStatus = fields['payment_status']?['stringValue']?.toUpperCase();
        if (isLicenseActive || paymentStatus == 'PAID' || paymentStatus == 'SUCCESS') {
          if (!_isLicenseActivated) {
            // Only auto-unlock this computer if it is within the 2-seat limit
            if (!_isSeatLimitReached) {
              final validityDays = int.tryParse(fields['validity_days']?['integerValue']?.toString() ?? '') ?? 365;
              final internalLicenseId = fields['internal_license_id']?['stringValue'] ?? 'GOOGLE-$emailDocId';
              await activateLicense(
                licenseKey: internalLicenseId,
                validityDays: validityDays,
                quotaBytes: reconciledQuota,
              );
            }
          }
        }

        // Push reconciled counts back to user doc
        await _patchUserQuotaToFirestore(client, emailDocId);
        // Also update local client document to link user
        if (clientId.isNotEmpty) {
          await _patchQuotaToFirestore(client, clientId);
        }
        notifyListeners();
      } else if (resp.statusCode == 404) {
        // First time Google user document: push current local counts
        await _patchUserQuotaToFirestore(client, emailDocId);
      }
      client.close();
    } catch (e) {
      debugPrint('Sync with Google account error: $e');
    }
  }

  Future<void> _patchUserQuotaToFirestore(HttpClient client, String emailDocId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'fields': {
        'bytes_slimmed': {'integerValue': _totalBytesSlimmed.toString()},
        'tb_slimmed': {'doubleValue': double.parse(totalTbSlimmed.toStringAsFixed(4))},
        'bytes_saved': {'integerValue': _totalBytesSaved.toString()},
        'files_count': {'integerValue': _totalFilesSlimmed.toString()},
        'quota_limit_bytes': {'integerValue': _quotaLimitBytes.toString()},
        'quota_limit_tb': {'doubleValue': double.parse(quotaLimitTb.toStringAsFixed(1))},
        'last_slimmed_at': {'stringValue': _lastSlimmedAt?.toIso8601String() ?? nowIso},
      }
    };

    final fieldsQuery = 'updateMask.fieldPaths=bytes_slimmed'
        '&updateMask.fieldPaths=tb_slimmed'
        '&updateMask.fieldPaths=bytes_saved'
        '&updateMask.fieldPaths=files_count'
        '&updateMask.fieldPaths=quota_limit_bytes'
        '&updateMask.fieldPaths=quota_limit_tb'
        '&updateMask.fieldPaths=last_slimmed_at';

    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/user_$emailDocId?$fieldsQuery&key=$apiKey',
    );
    final req = await client.patchUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(payload));
    final resp = await req.close();
    await resp.drain();
  }
}
