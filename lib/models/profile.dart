class UserProfile {
  UserProfile({
    required this.name,
    this.avatarPath,
    this.signature = '',
  });

  String name;
  String? avatarPath;
  String signature;

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatarPath,
        'signature': signature,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : '我',
        avatarPath: json['avatar'] as String?,
        signature: json['signature'] as String? ?? '',
      );

  UserProfile copyWith({String? name, String? avatarPath, String? signature}) =>
      UserProfile(
        name: name ?? this.name,
        avatarPath: avatarPath ?? this.avatarPath,
        signature: signature ?? this.signature,
      );
}

class BotProfile {
  BotProfile({required this.name, this.avatarPath, this.signature = ''});

  String name;
  String? avatarPath;
  String signature;

  Map<String, dynamic> toJson() => {
        'name': name,
        'avatar': avatarPath,
        'signature': signature,
      };

  factory BotProfile.fromJson(Map<String, dynamic> json) => BotProfile(
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : '大肥鱼',
        avatarPath: json['avatar'] as String?,
        signature: json['signature'] as String? ?? '',
      );

  BotProfile copyWith({String? name, String? avatarPath, String? signature}) =>
      BotProfile(
        name: name ?? this.name,
        avatarPath: avatarPath ?? this.avatarPath,
        signature: signature ?? this.signature,
      );
}
