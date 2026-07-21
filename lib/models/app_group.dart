class AppGroup {
  String name;
  List<String> packageNames;
  int timeLimitMinutes;

  AppGroup({
    required this.name,
    required this.packageNames,
    required this.timeLimitMinutes,
  });

  int getRemainingTime(int totalUsageMinutes, {int bonusMinutes = 0}) {
    final effective = timeLimitMinutes + bonusMinutes - totalUsageMinutes;
    return effective < 0 ? 0 : effective;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'packageNames': packageNames,
    'timeLimitMinutes': timeLimitMinutes,
  };

  factory AppGroup.fromJson(Map<String, dynamic> json) => AppGroup(
    name: json['name'] as String,
    packageNames: List<String>.from(json['packageNames'] as List),
    timeLimitMinutes: json['timeLimitMinutes'] as int,
  );
}
