class Moment {
  Moment({
    required this.id,
    required this.text,
    this.imagePath,
    required this.createdAt,
    this.liked = false,
    this.isBot = false,
  });

  final String id;
  String text;
  final String? imagePath;
  final int createdAt;
  bool liked;

  /// 是否为大肥鱼发的动态；false 表示用户自己发的。
  final bool isBot;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'imagePath': imagePath,
        'createdAt': createdAt,
        'liked': liked,
        'isBot': isBot,
      };

  factory Moment.fromJson(Map<String, dynamic> json) => Moment(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        imagePath: json['imagePath'] as String?,
        createdAt: json['createdAt'] as int? ?? 0,
        liked: json['liked'] as bool? ?? false,
        isBot: json['isBot'] as bool? ?? false,
      );
}
