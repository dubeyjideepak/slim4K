class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final DateTime? loggedInAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.loggedInAt,
  });

  bool get isValid => email.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'loggedInAt': loggedInAt?.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    uid: json['uid'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    photoUrl: json['photoUrl'] as String?,
    loggedInAt: json['loggedInAt'] != null ? DateTime.tryParse(json['loggedInAt'] as String) : null,
  );
}
