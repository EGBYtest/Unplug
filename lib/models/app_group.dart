class BannedFeature {
  final String id;
  final String name;
  final String packageName;
  bool isEnabled;
  final List<String> contentKeywords;
  final String? activityPattern;

  BannedFeature({
    required this.id,
    required this.name,
    required this.packageName,
    this.isEnabled = true,
    required this.contentKeywords,
    this.activityPattern,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'packageName': packageName,
    'isEnabled': isEnabled,
    'contentKeywords': contentKeywords,
    if (activityPattern != null) 'activityPattern': activityPattern,
  };

  factory BannedFeature.fromJson(Map<String, dynamic> json) => BannedFeature(
    id: json['id'] as String? ?? json['name'] as String,
    name: json['name'] as String,
    packageName: json['packageName'] as String? ?? '',
    isEnabled: json['isEnabled'] as bool? ?? true,
    contentKeywords: json['contentKeywords'] != null
        ? List<String>.from(json['contentKeywords'] as List)
        : [],
    activityPattern: json['activityPattern'] as String?,
  );
}

class AppGroup {
  String name;
  List<String> packageNames;
  int timeLimitMinutes;
  List<BannedFeature> bannedFeatures;

  AppGroup({
    required this.name,
    required this.packageNames,
    required this.timeLimitMinutes,
    List<BannedFeature>? bannedFeatures,
  }) : bannedFeatures = bannedFeatures ?? [];

  int getRemainingTime(int totalUsageMinutes, {int bonusMinutes = 0}) {
    final effective = timeLimitMinutes + bonusMinutes - totalUsageMinutes;
    return effective < 0 ? 0 : effective;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'packageNames': packageNames,
    'timeLimitMinutes': timeLimitMinutes,
    'bannedFeatures': bannedFeatures.map((b) => b.toJson()).toList(),
  };

  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
    name: json['name'] as String,
    packageNames: List<String>.from(json['packageNames'] as List),
    timeLimitMinutes: json['timeLimitMinutes'] as int,
    bannedFeatures: json['bannedFeatures'] != null
        ? (json['bannedFeatures'] as List)
            .map((e) => BannedFeature.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : [],
  );
}

