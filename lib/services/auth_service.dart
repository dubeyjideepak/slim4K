import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import 'keychain_service.dart';
import 'quota_service.dart';

/// Represents the seat allocation status for an active Google account (capped at 2 PCs)
class DeviceSeatStatus {
  final bool isAllowed;
  final int maxSeats;
  final List<String> activeDevices;
  final bool seatLimitExceeded;
  final String? invoiceId;

  const DeviceSeatStatus({
    required this.isAllowed,
    required this.maxSeats,
    required this.activeDevices,
    this.seatLimitExceeded = false,
    this.invoiceId,
  });
}

/// Manages Google Authentication, user session persistence,
/// 2-device seat allocation, and multi-device synchronization.
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final KeychainService _keychain = KeychainService();

  UserProfile? _currentUser;
  UserProfile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _currentUser!.isValid;

  bool _isSigningIn = false;
  bool get isSigningIn => _isSigningIn;

  DeviceSeatStatus? _currentSeatStatus;
  DeviceSeatStatus? get currentSeatStatus => _currentSeatStatus;

  String? _googleClientId;
  HttpServer? _loopbackServer;

  /// Initializes auth session from secure Keychain
  Future<void> initialize() async {
    try {
      _currentUser = await _keychain.getGoogleUserProfile();
      if (_currentUser != null) {
        debugPrint('Loaded authenticated Google user: ${_currentUser!.email}');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('AuthService init error: $e');
    }
  }

  /// Sanitizes email for use as a Firestore document ID
  static String emailToDocId(String email) {
    return email.trim().toLowerCase().replaceAll('@', '_at_').replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
  }

  /// Initiates Google Sign-In via standard Desktop OAuth2 Loopback (RFC 8252)
  /// or interactive authentication.
  Future<UserProfile?> signInWithGoogle({
    required String hardwareClientId,
    String? preferredEmail,
    String? customClientId,
  }) async {
    if (_isSigningIn) return null;
    _isSigningIn = true;
    notifyListeners();

    try {
      UserProfile? profile;

      // 1. Check if preferredEmail was provided (direct login or test bypass)
      if (preferredEmail != null && preferredEmail.contains('@')) {
        final email = preferredEmail.trim().toLowerCase();
        final name = email.split('@').first.replaceAll('.', ' ');
        profile = UserProfile(
          uid: 'google_${emailToDocId(email)}',
          email: email,
          displayName: name.isNotEmpty ? name[0].toUpperCase() + name.substring(1) : email,
          photoUrl: 'https://www.gravatar.com/avatar/${email.hashCode}?d=identicon',
          loggedInAt: DateTime.now(),
        );
      } else {
        // 2. Perform Desktop Browser OAuth2 Loopback Flow
        profile = await _performDesktopOAuthLoopback(customClientId: customClientId);
      }

      if (profile != null) {
        _currentUser = profile;
        await _keychain.setGoogleUserProfile(profile);

        // 3. Link this machine hardware ID to the Google account in Firestore
        await linkDeviceToGoogleAccount(
          user: profile,
          hardwareClientId: hardwareClientId,
        );

        // 4. Synchronize user quota & check if this Google account already owns a 10 TB license
        await QuotaService().syncWithGoogleAccount(user: profile, clientId: hardwareClientId);

        notifyListeners();
        return profile;
      }
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      rethrow;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
    return null;
  }

  /// Desktop OAuth2 Loopback Flow (RFC 8252)
  Future<UserProfile?> _performDesktopOAuthLoopback({String? customClientId}) async {
    _loopbackServer?.close(force: true);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _loopbackServer = server;
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port';

    final clientId = customClientId ?? _googleClientId;

    final completer = Completer<UserProfile?>();

    // Fallback timer if user closes browser window without completing
    final timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (!completer.isCompleted) {
        server.close(force: true);
        completer.complete(null);
      }
    });

    server.listen((HttpRequest request) async {
      try {
        final uri = request.uri;
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        final token = uri.queryParameters['id_token'] ?? uri.queryParameters['access_token'];

        // Return pleasant HTML response in user's browser
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <title>Slim4K - Authentication Successful</title>
  <style>
    body { background: #0D1117; color: #FFFFFF; font-family: sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #161B22; border: 1px solid #30363D; padding: 40px; border-radius: 16px; text-align: center; max-width: 420px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
    h2 { color: #00E5FF; margin-top: 0; }
    p { color: #8B949E; line-height: 1.5; font-size: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>✓ Sign-in Successful</h2>
    <p>Your Google account has been connected to <b>Slim4K</b>.<br>You can safely close this browser tab and return to the application.</p>
  </div>
</body>
</html>
''');
        await request.response.close();

        if (code != null) {
          // Exchange code or parse user info
          final userProfile = await _fetchGoogleProfileFromCode(code: code, redirectUri: redirectUri, clientId: clientId);
          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(userProfile);
          }
        } else if (token != null) {
          final userProfile = _decodeJwtOrToken(token);
          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(userProfile);
          }
        } else if (error != null) {
          if (!completer.isCompleted) {
            timeoutTimer.cancel();
            completer.complete(null);
          }
        }
      } catch (e) {
        debugPrint('Loopback request handling error: $e');
        if (!completer.isCompleted) completer.complete(null);
      } finally {
        server.close(force: true);
      }
    });

    // Launch browser
    final authUrl = _buildGoogleAuthUrl(redirectUri: redirectUri, clientId: clientId);
    _openBrowser(authUrl);

    return completer.future;
  }

  String _buildGoogleAuthUrl({required String redirectUri, String? clientId}) {
    final cId = clientId ?? '627494578132-u8190d6jckh8238.apps.googleusercontent.com'; // Default or provided
    return 'https://accounts.google.com/o/oauth2/v2/auth'
        '?client_id=$cId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&response_type=code'
        '&scope=${Uri.encodeComponent('openid email profile')}'
        '&prompt=select_account';
  }

  void _openBrowser(String url) {
    try {
      if (!kIsWeb && Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (!kIsWeb && Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (!kIsWeb && Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (e) {
      debugPrint('Failed to open browser: $e');
    }
  }

  Future<UserProfile?> _fetchGoogleProfileFromCode({
    required String code,
    required String redirectUri,
    String? clientId,
  }) async {
    // If running in dev/local environment where client secret is not on client binary,
    // extract profile or decode standard payload
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://oauth2.googleapis.com/token');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');

      final body = 'code=$code&client_id=${clientId ?? ''}&redirect_uri=${Uri.encodeComponent(redirectUri)}&grant_type=authorization_code';
      req.write(body);
      final resp = await req.close();
      final respStr = await utf8.decoder.bind(resp).join();
      final json = jsonDecode(respStr) as Map<String, dynamic>;

      if (json['id_token'] != null) {
        return _decodeJwtOrToken(json['id_token'] as String);
      }
    } catch (_) {}
    return null;
  }

  UserProfile? _decodeJwtOrToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length >= 2) {
        var payload = parts[1];
        while (payload.length % 4 != 0) {
          payload += '=';
        }
        final decoded = utf8.decode(base64Url.decode(payload));
        final map = jsonDecode(decoded) as Map<String, dynamic>;
        final email = map['email']?.toString() ?? '';
        final name = map['name']?.toString() ?? email.split('@').first;
        final photo = map['picture']?.toString();
        final sub = map['sub']?.toString() ?? email;

        if (email.isNotEmpty) {
          return UserProfile(
            uid: sub,
            email: email,
            displayName: name,
            photoUrl: photo,
            loggedInAt: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('JWT decode error: $e');
    }
    return null;
  }

  /// Links the current machine (hardwareClientId) with the Google Account in Firestore
  /// and enforces the 2-device seat cap.
  Future<DeviceSeatStatus> linkDeviceToGoogleAccount({
    required UserProfile user,
    required String hardwareClientId,
  }) async {
    const maxSeats = 2;
    if (hardwareClientId.isEmpty) {
      return const DeviceSeatStatus(isAllowed: true, maxSeats: maxSeats, activeDevices: []);
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);

      final userDocId = emailToDocId(user.email);

      // 1. Fetch current user document to inspect active_devices
      final fetchUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$userDocId?key=${QuotaService.apiKey}',
      );
      final fetchReq = await client.getUrl(fetchUri);
      final fetchResp = await fetchReq.close();

      List<String> activeDevices = [];
      String? invoiceId;

      if (fetchResp.statusCode == 200) {
        final body = await utf8.decoder.bind(fetchResp).join();
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};

        final rawDevices = fields['active_devices']?['arrayValue']?['values'] as List<dynamic>?;
        if (rawDevices != null) {
          activeDevices = rawDevices
              .map((v) => v['stringValue']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
        }
        invoiceId = fields['invoice_id']?['stringValue'];
      }

      // Check seat capacity
      final isAlreadyRegistered = activeDevices.contains(hardwareClientId);
      final isSeatLimitExceeded = !isAlreadyRegistered && activeDevices.length >= maxSeats;

      if (!isAlreadyRegistered && !isSeatLimitExceeded) {
        activeDevices.add(hardwareClientId);
      }

      // 2. Update apps/slim4k/users/{userDocId}
      final userUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$userDocId'
        '?updateMask.fieldPaths=email&updateMask.fieldPaths=display_name&updateMask.fieldPaths=photo_url&updateMask.fieldPaths=last_login_at&updateMask.fieldPaths=max_active_devices&updateMask.fieldPaths=active_devices&key=${QuotaService.apiKey}',
      );

      final userPatch = await client.patchUrl(userUri);
      userPatch.headers.contentType = ContentType.json;
      userPatch.write(jsonEncode({
        'fields': {
          'email': {'stringValue': user.email},
          'display_name': {'stringValue': user.displayName},
          'photo_url': {'stringValue': user.photoUrl ?? ''},
          'last_login_at': {'stringValue': DateTime.now().toIso8601String()},
          'max_active_devices': {'integerValue': maxSeats.toString()},
          'active_devices': {
            'arrayValue': {
              'values': activeDevices.map((d) => {'stringValue': d}).toList(),
            }
          }
        }
      }));
      final userResp = await userPatch.close();
      await userResp.drain();

      // 3. Update apps/slim4k/clients/{hardwareClientId} to tag the linked Google account
      final clientUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/$hardwareClientId'
        '?updateMask.fieldPaths=linked_google_email&updateMask.fieldPaths=linked_user_id&key=${QuotaService.apiKey}',
      );

      final clientPatch = await client.patchUrl(clientUri);
      clientPatch.headers.contentType = ContentType.json;
      clientPatch.write(jsonEncode({
        'fields': {
          'linked_google_email': {'stringValue': user.email},
          'linked_user_id': {'stringValue': user.uid},
        }
      }));
      final clientResp = await clientPatch.close();
      await clientResp.drain();

      client.close();

      _currentSeatStatus = DeviceSeatStatus(
        isAllowed: !isSeatLimitExceeded,
        maxSeats: maxSeats,
        activeDevices: activeDevices,
        seatLimitExceeded: isSeatLimitExceeded,
        invoiceId: invoiceId,
      );
      notifyListeners();
      return _currentSeatStatus!;
    } catch (e) {
      debugPrint('Link device error: $e');
      return const DeviceSeatStatus(isAllowed: true, maxSeats: 2, activeDevices: []);
    }
  }

  /// Transfers a seat by deactivating an old device and activating the new machine
  Future<bool> transferDeviceSeat({
    required UserProfile user,
    required String oldHardwareClientId,
    required String newHardwareClientId,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final userDocId = emailToDocId(user.email);

      // 1. Fetch user doc to get active_devices
      final fetchUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$userDocId?key=${QuotaService.apiKey}',
      );
      final fetchReq = await client.getUrl(fetchUri);
      final fetchResp = await fetchReq.close();
      List<String> activeDevices = [];

      if (fetchResp.statusCode == 200) {
        final body = await utf8.decoder.bind(fetchResp).join();
        final doc = jsonDecode(body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};
        final rawDevices = fields['active_devices']?['arrayValue']?['values'] as List<dynamic>?;
        if (rawDevices != null) {
          activeDevices = rawDevices
              .map((v) => v['stringValue']?.toString() ?? '')
              .where((s) => s.isNotEmpty && s != oldHardwareClientId)
              .toList();
        }
      }

      if (!activeDevices.contains(newHardwareClientId)) {
        activeDevices.add(newHardwareClientId);
      }

      // 2. Update user doc with new active_devices
      final patchUserUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/user_$userDocId'
        '?updateMask.fieldPaths=active_devices&key=${QuotaService.apiKey}',
      );
      final patchReq = await client.patchUrl(patchUserUri);
      patchReq.headers.contentType = ContentType.json;
      patchReq.write(jsonEncode({
        'fields': {
          'active_devices': {
            'arrayValue': {
              'values': activeDevices.map((d) => {'stringValue': d}).toList(),
            }
          }
        }
      }));
      final patchResp = await patchReq.close();
      await patchResp.drain();

      // 3. Deactivate old client in Firestore
      final deactUri = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/${QuotaService.projectId}/databases/(default)/documents/apps/slim4k/clients/$oldHardwareClientId'
        '?updateMask.fieldPaths=is_license_activated&key=${QuotaService.apiKey}',
      );
      final deactReq = await client.patchUrl(deactUri);
      deactReq.headers.contentType = ContentType.json;
      deactReq.write(jsonEncode({
        'fields': {
          'is_license_activated': {'booleanValue': false},
        }
      }));
      final deactResp = await deactReq.close();
      await deactResp.drain();

      client.close();

      _currentSeatStatus = DeviceSeatStatus(
        isAllowed: true,
        maxSeats: 2,
        activeDevices: activeDevices,
        seatLimitExceeded: false,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Seat transfer error: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut({String? hardwareClientId}) async {
    _currentUser = null;
    await _keychain.clearGoogleUserProfile();
    notifyListeners();
  }
}
