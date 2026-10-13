enum ActivationStatus {
  active,
  offlineGrace,
  deactivatedExpired,
  deactivatedAdmin,
  checking,
}

class ClientActivation {
  static const String currentAppId = 'slim4k';

  final String appId;
  final String clientId;
  final String platform;
  bool isActive;
  DateTime lastHeartbeat;
  DateTime firstRegisteredAt;
  ActivationStatus status;
  String? deactivationReason;

  ClientActivation({
    this.appId = currentAppId,
    required this.clientId,
    required this.platform,
    this.isActive = true,
    required this.lastHeartbeat,
    required this.firstRegisteredAt,
    this.status = ActivationStatus.checking,
    this.deactivationReason,
  });

  int get daysSinceLastHeartbeat {
    final diff = DateTime.now().difference(lastHeartbeat);
    return diff.inDays < 0 ? 0 : diff.inDays;
  }

  int get daysRemainingBeforeExpiry {
    const maxDays = 15;
    final remaining = maxDays - daysSinceLastHeartbeat;
    return remaining < 0 ? 0 : remaining;
  }

  Map<String, dynamic> toJson() => {
    'app_id': appId,
    'client_id': clientId,
    'platform': platform,
    'is_active': isActive,
    'last_heartbeat': lastHeartbeat.toIso8601String(),
    'first_registered_at': firstRegisteredAt.toIso8601String(),
    'deactivation_reason': deactivationReason,
  };

  factory ClientActivation.fromJson(Map<String, dynamic> json) {
    return ClientActivation(
      appId: json['app_id']?.toString() ?? currentAppId,
      clientId: json['client_id']?.toString() ?? '',
      platform: json['platform']?.toString() ?? 'unknown',
      isActive: json['is_active'] == true,
      lastHeartbeat: DateTime.tryParse(json['last_heartbeat']?.toString() ?? '') ?? DateTime.now(),
      firstRegisteredAt: DateTime.tryParse(json['first_registered_at']?.toString() ?? '') ?? DateTime.now(),
      deactivationReason: json['deactivation_reason']?.toString(),
    );
  }
}
