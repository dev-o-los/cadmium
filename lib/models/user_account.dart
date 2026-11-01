import 'dart:convert';

/// Represents a signed-in Google account with YouTube Music authorization.
class UserAccount {
  final String id;
  final String displayName;
  final String email;
  final String? avatarUrl;
  final String cookies;
  final DateTime connectedAt;
  final bool isPersonalizedEnabled;

  const UserAccount({
    required this.id,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    required this.cookies,
    required this.connectedAt,
    this.isPersonalizedEnabled = true,
  });

  /// Extracts SAPISID or __Secure-3PAPISID token from the cookie string
  String? get sapisid {
    final regex = RegExp(r'(?:SAPISID|__Secure-3PAPISID)=([^;]+)');
    final match = regex.firstMatch(cookies);
    return match?.group(1)?.trim();
  }

  /// Initial letters of display name for fallback avatar circle
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  UserAccount copyWith({
    String? id,
    String? displayName,
    String? email,
    String? avatarUrl,
    String? cookies,
    DateTime? connectedAt,
    bool? isPersonalizedEnabled,
  }) {
    return UserAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      cookies: cookies ?? this.cookies,
      connectedAt: connectedAt ?? this.connectedAt,
      isPersonalizedEnabled:
          isPersonalizedEnabled ?? this.isPersonalizedEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
      'cookies': cookies,
      'connectedAt': connectedAt.toIso8601String(),
      'isPersonalizedEnabled': isPersonalizedEnabled,
    };
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: json['id'] as String? ?? 'ytm_user',
      displayName: json['displayName'] as String? ?? 'YouTube Music User',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      cookies: json['cookies'] as String? ?? '',
      connectedAt: json['connectedAt'] != null
          ? DateTime.tryParse(json['connectedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isPersonalizedEnabled: json['isPersonalizedEnabled'] as bool? ?? true,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory UserAccount.fromJsonString(String source) =>
      UserAccount.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          cookies == other.cookies &&
          isPersonalizedEnabled == other.isPersonalizedEnabled;

  @override
  int get hashCode =>
      id.hashCode ^
      email.hashCode ^
      cookies.hashCode ^
      isPersonalizedEnabled.hashCode;
}

