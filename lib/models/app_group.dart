import 'banned_feature.dart';

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

  bool get hasBannedFeatures => bannedFeatures.isNotEmpty;

  int getRemainingTime(int totalUsageMinutes, {int bonusMinutes = 0}) {
    final effective = timeLimitMinutes + bonusMinutes - totalUsageMinutes;
    return effective < 0 ? 0 : effective;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'packageNames': packageNames,
    'timeLimitMinutes': timeLimitMinutes,
    'bannedFeatures': bannedFeatures.map((f) => f.toJson()).toList(),
  };

  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
    name: json['name'] as String,
    packageNames: List<String>.from(json['packageNames'] as List),
    timeLimitMinutes: json['timeLimitMinutes'] as int,
    bannedFeatures: json['bannedFeatures'] != null
        ? (json['bannedFeatures'] as List)
            .map((e) => BannedFeature.fromJson(e as Map<String, dynamic>))
            .toList()
        : [],
  );
}
