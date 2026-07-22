import 'package:flutter_test/flutter_test.dart';
import 'package:unplug/models/app_group.dart';

void main() {
  group('BannedFeature & AppGroup tests', () {
    test('BannedFeature serialization & deserialization', () {
      final feature = BannedFeature(
        id: 'yt_shorts',
        name: 'YouTube Shorts',
        packageName: 'com.google.android.youtube',
        isEnabled: true,
        contentKeywords: ['shorts', 'reel_player'],
        activityPattern: '.*shorts.*',
      );

      final json = feature.toJson();
      expect(json['id'], equals('yt_shorts'));
      expect(json['name'], equals('YouTube Shorts'));
      expect(json['packageName'], equals('com.google.android.youtube'));
      expect(json['isEnabled'], equals(true));
      expect(json['contentKeywords'], contains('shorts'));

      final restored = BannedFeature.fromJson(json);
      expect(restored.id, equals('yt_shorts'));
      expect(restored.name, equals('YouTube Shorts'));
      expect(restored.packageName, equals('com.google.android.youtube'));
      expect(restored.isEnabled, isTrue);
      expect(restored.contentKeywords, equals(['shorts', 'reel_player']));
      expect(restored.activityPattern, equals('.*shorts.*'));
    });

    test('AppGroup with bannedFeatures serialization', () {
      final group = AppGroup(
        name: 'Entertainment',
        packageNames: ['com.google.android.youtube'],
        timeLimitMinutes: 60,
        bannedFeatures: [
          BannedFeature(
            id: 'yt_shorts',
            name: 'YouTube Shorts',
            packageName: 'com.google.android.youtube',
            contentKeywords: ['shorts'],
          ),
        ],
      );

      final json = group.toJson();
      expect(json['bannedFeatures'], isNotNull);
      final restored = AppGroup.fromJson(json);
      expect(restored.name, equals('Entertainment'));
      expect(restored.bannedFeatures.length, equals(1));
      expect(restored.bannedFeatures.first.name, equals('YouTube Shorts'));
    });
  });
}
