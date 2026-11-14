/// A remote list of routes the user follows, shown as a folder.
///
/// Stored as JSON inside the encrypted settings box because the URL usually
/// carries a private access token.
class Subscription {
  final String id;
  final String url;
  final String name;

  /// True once the user renamed the folder; provider titles no longer apply.
  final bool hasCustomName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? lastError;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expiresAt;

  /// Automatic refresh period in hours; 0 turns it off.
  final int autoUpdateHours;

  const Subscription({
    required this.id,
    required this.url,
    required this.name,
    required this.createdAt,
    this.hasCustomName = false,
    this.updatedAt,
    this.lastError,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expiresAt,
    this.autoUpdateHours = 12,
  });

  int? get usedBytes => uploadBytes == null && downloadBytes == null
      ? null
      : (uploadBytes ?? 0) + (downloadBytes ?? 0);

  /// Share of the data allowance already used, or null when unknown/unlimited.
  double? get usageFraction {
    final total = totalBytes;
    final used = usedBytes;
    if (total == null || total <= 0 || used == null) return null;
    return (used / total).clamp(0.0, 1.0);
  }

  /// Whole days until expiry; negative once expired; null when unknown.
  int? daysLeft([DateTime? now]) {
    final expiry = expiresAt;
    if (expiry == null) return null;
    final diff = expiry.difference(now ?? DateTime.now());
    return diff.isNegative ? -1 : (diff.inHours / 24).ceil();
  }

  bool isDue([DateTime? now]) {
    if (autoUpdateHours <= 0) return false;
    final last = updatedAt;
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >=
        Duration(hours: autoUpdateHours);
  }

  Subscription copyWith({
    String? name,
    bool? hasCustomName,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
    int? uploadBytes,
    int? downloadBytes,
    int? totalBytes,
    DateTime? expiresAt,
    bool clearUsage = false,
    int? autoUpdateHours,
  }) {
    return Subscription(
      id: id,
      url: url,
      name: name ?? this.name,
      createdAt: createdAt,
      hasCustomName: hasCustomName ?? this.hasCustomName,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      uploadBytes: clearUsage ? uploadBytes : (uploadBytes ?? this.uploadBytes),
      downloadBytes: clearUsage
          ? downloadBytes
          : (downloadBytes ?? this.downloadBytes),
      totalBytes: clearUsage ? totalBytes : (totalBytes ?? this.totalBytes),
      expiresAt: clearUsage ? expiresAt : (expiresAt ?? this.expiresAt),
      autoUpdateHours: autoUpdateHours ?? this.autoUpdateHours,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'url': url,
    'name': name,
    'hasCustomName': hasCustomName,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'lastError': lastError,
    'uploadBytes': uploadBytes,
    'downloadBytes': downloadBytes,
    'totalBytes': totalBytes,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'autoUpdateHours': autoUpdateHours,
  };

  static Subscription? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id']?.toString();
    final url = json['url']?.toString();
    if (id == null || url == null) return null;
    DateTime? date(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    int? number(Object? value) =>
        value is int ? value : int.tryParse(value?.toString() ?? '');
    return Subscription(
      id: id,
      url: url,
      name: json['name']?.toString() ?? url,
      hasCustomName: json['hasCustomName'] == true,
      createdAt: date(json['createdAt']) ?? DateTime.now(),
      updatedAt: date(json['updatedAt']),
      lastError: json['lastError']?.toString(),
      uploadBytes: number(json['uploadBytes']),
      downloadBytes: number(json['downloadBytes']),
      totalBytes: number(json['totalBytes']),
      expiresAt: date(json['expiresAt']),
      autoUpdateHours: number(json['autoUpdateHours']) ?? 12,
    );
  }
}
