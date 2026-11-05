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
  final String? dataSyncId;
  final String? pageId;
  final String? authUser;
  final String? visitorData;

  const UserAccount({
    required this.id,
    required this.displayName,
    required this.email,
    this.avatarUrl,
    required this.cookies,
    required this.connectedAt,
    this.isPersonalizedEnabled = true,
    this.dataSyncId,
    this.pageId,
    this.authUser,
    this.visitorData,
  });

  /// Extracts SAPISID, __Secure-3PAPISID, or __Secure-1PAPISID token from the cookie string
  String? get sapisid {
    final jar = <String, String>{};
    for (final part in cookies.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        jar[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
      }
    }
    return jar['SAPISID'] ?? jar['__Secure-3PAPISID'] ?? jar['__Secure-1PAPISID'];
  }

  /// Normalizes DATASYNC_ID as in BitChord (handling account||delegated forms)
  static String? normalizeDataSyncId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    if (!value.contains('||')) return value;
    final after = value.substring(value.indexOf('||') + 2).trim();
    if (after.isNotEmpty) return after;
    final before = value.substring(0, value.indexOf('||')).trim();
    return before.isNotEmpty ? before : null;
  }

  /// Upgrades avatar URL to crisp resolution (256x256) and ensures https
  static String? cleanAvatarUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var cleaned = url.trim();
    if (cleaned.startsWith('//')) {
      cleaned = 'https:$cleaned';
    }
    // Upgrades common low-res sizes (=s88, =s64, =s32, etc.) to 256
    cleaned = cleaned.replaceAll(RegExp(r'=s\d+(-c)?'), '=s256-c');
    return cleaned;
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
    String? dataSyncId,
    String? pageId,
    String? authUser,
    String? visitorData,
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
      dataSyncId: dataSyncId ?? this.dataSyncId,
      pageId: pageId ?? this.pageId,
      authUser: authUser ?? this.authUser,
      visitorData: visitorData ?? this.visitorData,
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
      'dataSyncId': dataSyncId,
      'pageId': pageId,
      'authUser': authUser,
      'visitorData': visitorData,
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
      dataSyncId: json['dataSyncId'] as String?,
      pageId: json['pageId'] as String?,
      authUser: json['authUser'] as String?,
      visitorData: json['visitorData'] as String?,
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

