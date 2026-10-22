import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/app_activation.dart';
import 'keychain_service.dart';
import 'quota_service.dart';

class ActivationService {
  static final ActivationService _instance = ActivationService._internal();
  factory ActivationService() => _instance;
  ActivationService._internal();

  static const String projectId = 'appactivations-f47d0';
  static const String apiKey = 'AIzaSyBp4GOH_XBhYgqNbRW9RpeIjUhFX7soWA4';
  static const String appId = ClientActivation.currentAppId;

  ClientActivation? _currentActivation;
  ClientActivation? get currentActivation => _currentActivation;

  String get currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Path to local persistent activation cache
  Future<File> _getConfigFile() async {
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
    return File(p.join(dir.path, 'slim4k_activation_cache.json'));
  }

  /// Generates a unique, persistent client_id for this machine/installation
  String _generateUniqueClientId() {
    final rand = Random.secure();
    final randomHex = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return 'c_${currentPlatform}_${randomHex}_$timestamp';
  }

  /// Loads locally persisted activation, or creates a new one (Keychain-resilient across reinstalls)
  Future<ClientActivation> loadOrCreateLocalActivation() async {
    // 1. Check hardware Keychain first for persistent device ID (survives app re-install)
    final keychainClientId = await KeychainService().getClientId();

    final file = await _getConfigFile();
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final activation = ClientActivation.fromJson(json);
        if (activation.clientId.isNotEmpty) {
          // If keychain has an established id, prefer it to prevent divergence
          final resolvedId = (keychainClientId != null && keychainClientId.isNotEmpty)
              ? keychainClientId
              : activation.clientId;
          await KeychainService().setClientId(resolvedId);

          final updatedActivation = ClientActivation(
            appId: activation.appId,
            clientId: resolvedId,
            platform: activation.platform,
            isActive: activation.isActive,
            lastHeartbeat: activation.lastHeartbeat,
            firstRegisteredAt: activation.firstRegisteredAt,
            status: activation.status,
            deactivationReason: activation.deactivationReason,
          );
          _currentActivation = updatedActivation;
          return updatedActivation;
        }
      } catch (e) {
        debugPrint('Error loading cached activation: $e');
      }
    }

    // First time setup OR fresh re-installation:
    // If keychain already has a clientId, reuse it so quota & history restore!
    final clientId = (keychainClientId != null && keychainClientId.isNotEmpty)
        ? keychainClientId
        : _generateUniqueClientId();

    await KeychainService().setClientId(clientId);

    final now = DateTime.now();
    final newActivation = ClientActivation(
      appId: appId,
      clientId: clientId,
      platform: currentPlatform,
      isActive: true, // Default true as requested
      lastHeartbeat: now,
      firstRegisteredAt: now,
      status: ActivationStatus.checking,
    );

    await _saveLocalActivation(newActivation);
    _currentActivation = newActivation;
    return newActivation;
  }

  Future<void> _saveLocalActivation(ClientActivation activation) async {
    try {
      final file = await _getConfigFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(activation.toJson()));
    } catch (e) {
      debugPrint('Error saving local activation: $e');
    }
  }

  /// Verifies license and syncs daily heartbeat with Firestore
  Future<ClientActivation> verifyAndSync({bool forceOnline = false}) async {
    final activation = _currentActivation ?? await loadOrCreateLocalActivation();

    // Initialize QuotaService with persistent clientId
    Future.microtask(() => QuotaService().initialize(clientId: activation.clientId));

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      // Endpoint 1: apps/{appId}/clients/{clientId}
      final clientUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/${activation.clientId}?key=$apiKey',
      );

      // Check if document exists on Firestore
      final getReq = await client.getUrl(clientUri);
      final getResp = await getReq.close();
      final getBody = await utf8.decoder.bind(getResp).join();

      if (getResp.statusCode == 404) {
        // Document doesn't exist yet on Firestore -> Register new client with is_active = true
        await _registerNewClientOnFirestore(client, activation);
        activation.isActive = true;
        activation.status = ActivationStatus.active;
        activation.lastHeartbeat = DateTime.now();
        await _saveLocalActivation(activation);
        client.close();
        return activation;
      }

      if (getResp.statusCode == 200) {
        final doc = jsonDecode(getBody) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final bool remoteIsActive = fields['is_active']?['booleanValue'] ?? true;
        final String? remoteHeartbeatStr = fields['last_heartbeat']?['stringValue'] ??
            fields['last_heartbeat']?['timestampValue'];
        final DateTime remoteHeartbeat = remoteHeartbeatStr != null
            ? (DateTime.tryParse(remoteHeartbeatStr) ?? activation.lastHeartbeat)
            : activation.lastHeartbeat;

        final daysDisconnected = DateTime.now().difference(remoteHeartbeat).inDays;

        // RULE 1: Admin deactivated directly in Firebase Console
        if (!remoteIsActive) {
          activation.isActive = false;
          activation.status = ActivationStatus.deactivatedAdmin;
          activation.deactivationReason = 'Deactivated by Administrator in Firebase Console';
          await _saveLocalActivation(activation);
          client.close();
          return activation;
        }

        // RULE 2: If disconnected for 15+ days -> Deactivate until activated from Firebase
        if (daysDisconnected >= 15) {
          activation.isActive = false;
          activation.status = ActivationStatus.deactivatedExpired;
          activation.deactivationReason = 'Disconnected for $daysDisconnected days (15-day limit exceeded)';
          await _updateFirestoreStatus(client, activation.clientId, isActive: false, reason: 'offline_exceeded_15_days');
          await _saveLocalActivation(activation);
          client.close();
          return activation;
        }

        // RULE 3: Client is active -> update daily heartbeat to Firestore
        final now = DateTime.now();
        await _sendHeartbeatToFirestore(client, activation.clientId, now);

        activation.isActive = true;
        activation.lastHeartbeat = now;
        activation.status = ActivationStatus.active;
        activation.deactivationReason = null;
        await _saveLocalActivation(activation);

        client.close();
        return activation;
      }

      client.close();
    } catch (e) {
      debugPrint('Firestore online sync error (offline or network issue): $e');
    }

    // OFFLINE FALLBACK LOGIC
    // Compare current time with local lastHeartbeat
    final localDaysOffline = activation.daysSinceLastHeartbeat;

    if (!activation.isActive) {
      activation.status = ActivationStatus.deactivatedAdmin;
    } else if (localDaysOffline >= 15) {
      activation.isActive = false;
      activation.status = ActivationStatus.deactivatedExpired;
      activation.deactivationReason = 'Offline for $localDaysOffline days (15-day limit exceeded)';
      await _saveLocalActivation(activation);
    } else if (localDaysOffline >= 1) {
      // Disconnected for more than 1 day but less than 15 days -> Offline Grace
      activation.status = ActivationStatus.offlineGrace;
    } else {
      activation.status = ActivationStatus.active;
    }

    return activation;
  }

  /// Registers a brand new client on Firestore with is_active = true
  Future<void> _registerNewClientOnFirestore(HttpClient client, ClientActivation activation) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final quota = QuotaService();

    final payload = {
      'fields': {
        'app_id': {'stringValue': activation.appId},
        'client_id': {'stringValue': activation.clientId},
        'platform': {'stringValue': activation.platform},
        'is_active': {'booleanValue': true},
        'last_heartbeat': {'stringValue': nowIso},
        'first_registered_at': {'stringValue': nowIso},
        'bytes_slimmed': {'integerValue': quota.totalBytesSlimmed.toString()},
        'tb_slimmed': {'doubleValue': double.parse(quota.totalTbSlimmed.toStringAsFixed(4))},
        'bytes_saved': {'integerValue': quota.totalBytesSaved.toString()},
        'files_count': {'integerValue': quota.totalFilesSlimmed.toString()},
        'quota_limit_bytes': {'integerValue': quota.quotaLimitBytes.toString()},
        'quota_limit_tb': {'doubleValue': double.parse(quota.quotaLimitTb.toStringAsFixed(1))},
      }
    };

    // 1. Write to /apps/{appId}/clients/{clientId}
    final uri1 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/${activation.clientId}?key=$apiKey',
    );
    final req1 = await client.patchUrl(uri1);
    req1.headers.contentType = ContentType.json;
    req1.write(jsonEncode(payload));
    final resp1 = await req1.close();
    await resp1.drain();

    // 2. Also mirror to /app_activations/{appId}_{clientId} for fast global query
    final uri2 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/app_activations/${appId}_${activation.clientId}?key=$apiKey',
    );
    final req2 = await client.patchUrl(uri2);
    req2.headers.contentType = ContentType.json;
    req2.write(jsonEncode(payload));
    final resp2 = await req2.close();
    await resp2.drain();
  }

  /// Updates last_heartbeat timestamp on Firestore
  Future<void> _sendHeartbeatToFirestore(HttpClient client, String clientId, DateTime now) async {
    final nowIso = now.toUtc().toIso8601String();
    final payload = {
      'fields': {
        'last_heartbeat': {'stringValue': nowIso},
      }
    };

    final uri1 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/$clientId?updateMask.fieldPaths=last_heartbeat&key=$apiKey',
    );
    final req1 = await client.patchUrl(uri1);
    req1.headers.contentType = ContentType.json;
    req1.write(jsonEncode(payload));
    final resp1 = await req1.close();
    await resp1.drain();

    final uri2 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/app_activations/${appId}_$clientId?updateMask.fieldPaths=last_heartbeat&key=$apiKey',
    );
    final req2 = await client.patchUrl(uri2);
    req2.headers.contentType = ContentType.json;
    req2.write(jsonEncode(payload));
    final resp2 = await req2.close();
    await resp2.drain();
  }

  /// Updates is_active and deactivation reason on Firestore
  Future<void> _updateFirestoreStatus(
    HttpClient client,
    String clientId, {
    required bool isActive,
    String? reason,
  }) async {
    final payload = {
      'fields': {
        'is_active': {'booleanValue': isActive},
        'deactivation_reason': {'stringValue': reason ?? ''},
      }
    };

    final uri1 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/apps/$appId/clients/$clientId?updateMask.fieldPaths=is_active&updateMask.fieldPaths=deactivation_reason&key=$apiKey',
    );
    final req1 = await client.patchUrl(uri1);
    req1.headers.contentType = ContentType.json;
    req1.write(jsonEncode(payload));
    final resp1 = await req1.close();
    await resp1.drain();

    final uri2 = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/app_activations/${appId}_$clientId?updateMask.fieldPaths=is_active&updateMask.fieldPaths=deactivation_reason&key=$apiKey',
    );
    final req2 = await client.patchUrl(uri2);
    req2.headers.contentType = ContentType.json;
    req2.write(jsonEncode(payload));
    final resp2 = await req2.close();
    await resp2.drain();
  }
}
