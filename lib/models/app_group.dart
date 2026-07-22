class AppGroup {
  String name;
  List<String> packageNames;
  int timeLimitMinutes;
  List<String> bannedFeatures;

  AppGroup({
    required this.name,
    required this.packageNames,
    required this.timeLimitMinutes,
    List<String>? bannedFeatures,
  }) : bannedFeatures = bannedFeatures ?? [];

  bool get hasBannedFeatures => bannedFeatures.isNotEmpty;

  int getRemainingTime(int totalUsageMinutes, {int bonusMinutes = 0}) {
    final effective = timeLimitMinutes + bonusMinutes - totalUsageMinutes;
    return effective < 0 ? 0 : effective;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'packageNames': packageNames,
    'timeLimitMinutes': timeLimitMinutes,
    'bannedFeatures': bannedFeatures,
  };

  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
    name: json['name'] as String,
    packageNames: List<String>.from(json['packageNames'] as List),
    timeLimitMinutes: json['timeLimitMinutes'] as int,
    bannedFeatures: json['bannedFeatures'] != null
        ? List<String>.from(json['bannedFeatures'] as List)
        : [],
  );
}
