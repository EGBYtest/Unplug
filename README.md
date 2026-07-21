# ScreenTimeLock

An Android screen time management app that helps you take control of your digital habits. Set daily time limits on groups of apps, and once exhausted, earn extra time by watching an ad or completing a typing challenge.

> **Privacy-first, open source.** All data is stored locally on your device. Nothing is ever sent to any server.

## Features

### App Group Limits
- Group apps into categories (e.g., Social Media, Games, Entertainment)
- Set a daily time limit per group (e.g., 30 min for social media)
- Groups with a 0-minute limit are blocked immediately

### Real-Time Enforcement
- An Android **Accessibility Service** listens for foreground app changes
- When you exceed a group's limit, the app is blocked and a non-dismissible lock screen popup appears
- Works with split-screen and Picture-in-Picture modes

### Bypass Mechanisms
Once your time is exhausted, you can earn bonus time by:

1. **Watch a Rewarded Ad** — Grants configurable bonus time (default: 1 minute per ad)
2. **Type 100 Words Challenge** — Manually type a 100-word message to prove intentionality. Copy-paste is blocked.

### Locked Settings
- Changing app limits requires watching an ad or passing the typing challenge
- Prevents impulse changes to time limits

### Privacy Dashboard
- Circular progress ring showing today's total screen time vs. limit
- Per-group usage breakdown with visual progress bars
- Color-coded indicators (green = safe, yellow = nearing limit, red = exhausted)

### Usage Statistics
- "Groups" stat card — number of app groups configured
- "Exhausted" stat card — groups that have hit their limit today
- "Active" stat card — groups still within their limit

## Architecture

```
ScreenTimeLock/
├── lib/                           # Flutter/Dart code
│   ├── main.dart                  # App entry point, CupertinoApp, method channel setup
│   ├── home_screen.dart           # Main dashboard with ring + stat cards + app tiles
│   ├── onboarding_screen.dart     # Permission setup flow
│   ├── settings_screen.dart       # Locked settings (watch ad / type to unlock)
│   ├── lock_screen_popup.dart     # Non-dismissible lock dialog with bypass options
│   ├── screens/
│   │   └── app_picker_screen.dart # Searchable list of installed apps (User/System tabs)
│   ├── models/
│   │   └── app_group.dart         # AppGroup model (name, packages, time limit)
│   ├── services/
│   │   ├── storage_service.dart   # SharedPreferences persistence (groups, bonuses, prefs)
│   │   ├── usage_tracker.dart     # Dart-side usage polling via usage_stats package
│   │   ├── app_closure_handler.dart # MethodChannel bridge to native Kotlin
│   │   ├── ad_reward_system.dart  # Google Mobile Ads rewarded ad integration
│   │   └── message_verification.dart # Typing challenge message generator/verifier
│   └── utils/
│       └── no_paste_formatter.dart # Blocks clipboard paste in text fields
├── android/
│   └── app/src/main/kotlin/com/example/app_idea/
│       ├── MainActivity.kt        # FlutterActivity, MethodChannel handler
│       ├── AppClosureHandler.kt   # Force-close / home screen redirect
│       └── UsageAccessibilityService.kt # AccessibilityService monitoring & enforcement
└── pubspec.yaml
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Local-only storage** | All data in SharedPreferences — no network calls, no server |
| **Kotlin Accessibility Service** | Needed to detect foreground app switches and block apps in real-time |
| **Dart-side usage stats** | Uses `usage_stats` package for the dashboard; native side re-reads SharedPreferences for enforcement |
| **MethodChannel bridge** | `app_closure` channel handles all Flutter ↔ Android communication |
| **Cupertino widgets** | iOS-style dark theme for a clean, premium feel |
| **Typing challenge** | Forces intentional, mindful decision to bypass limits |
| **No license** | All rights reserved |

## Permissions

ScreenTimeLock requires two Android permissions:

1. **Usage Access** (`PACKAGE_USAGE_STATS`) — Read app usage statistics to track screen time
2. **Accessibility Service** (`BIND_ACCESSIBILITY_SERVICE`) — Detect when a time-limited app is opened and enforce limits

Both are requested during onboarding and must be manually granted in system settings.

## Build & Run

```bash
# Clone the repository
git clone https://github.com/yourusername/screentimelock.git
cd screentimelock

# Get dependencies
flutter pub get

# Run on connected device (Android)
flutter run
```

> **Note:** The app currently uses Google Mobile Ads **test** ad unit IDs. Replace them with production IDs before releasing.

### Requirements
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android device/emulator (API 30+ recommended)

## Tech Stack

- **Framework:** Flutter (Cupertino widgets)
- **Language:** Dart + Kotlin (native)
- **Ads:** Google Mobile Ads SDK (rewarded video)
- **Storage:** SharedPreferences
- **Usage Stats:** `usage_stats` Flutter package
- **Build:** Flutter CLI, Gradle
