import 'dart:convert';

class Subscription {
  final String id;
  final String url;
  final String name;

  /// زمان آخرین به‌روزرسانی (میلی‌ثانیه از epoch)؛ null = هنوز نشده
  final int? updatedMs;

  const Subscription({
    required this.id,
    required this.url,
    required this.name,
    this.updatedMs,
  });

  Subscription copyWith({int? updatedMs}) => Subscription(
        id: id,
        url: url,
        name: name,
        updatedMs: updatedMs ?? this.updatedMs,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'url': url, 'name': name, 'updatedMs': updatedMs};

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        url: j['url'] as String,
        name: j['name'] as String,
        updatedMs: j['updatedMs'] as int?,
      );

  static String encodeList(List<Subscription> l) =>
      jsonEncode(l.map((e) => e.toJson()).toList());

  static List<Subscription> decodeList(String s) => (jsonDecode(s) as List)
      .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
      .toList();
}
