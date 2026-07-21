# ScreenTimeLock

> **v1.1 (Beta)** — Take control of your digital habits.

An Android screen time management app that helps you limit mindless app usage. Set daily time limits on app groups. Once exhausted, earn extra time by watching an ad or completing a typing challenge.

> **Privacy-first, open source.** All data stored locally. Nothing leaves your device.

---

## Screenshots

<p float="left">
  <img src="screenshots/home_dashboard.png" width="200" alt="Home Dashboard" />
  <img src="screenshots/app_picker.png" width="200" alt="App Picker" />
  <img src="screenshots/lock_screen.png" width="200" alt="Lock Screen" />
  <img src="screenshots/settings.png" width="200" alt="Settings" />
</p>

---

## Features

### App Group Limits
- Group apps into categories (Social Media, Games, Entertainment...)
- Set daily time limit per group (30 min, 1 hour, or 0 = block immediately)
- Saved locally, reset daily

### Real-Time Enforcement
- **Accessibility Service** detects foreground app switches
- Exceed limit → non-dismissible lock screen popup
- Works in split-screen and PiP mode

### Bypass Mechanisms
| Method | Bonus Time | Notes |
|--------|-----------|-------|
| Watch rewarded ad | +1 min (configurable) | Ad unit IDs in `ad_reward_system.dart` |
| Type 100-word challenge | +1 min | Copy-paste blocked; forces intentionality |

### Locked Settings
- Changing limits requires ad or typing challenge
- Toggle in Settings → SECURITY → Lock Settings
- Prevents impulse tweaks

### Privacy Dashboard
- Circular progress ring — total screen time vs. limit
- Per-group progress bars with color coding
  - 🟢 Green = safe
  - 🟡 Yellow = nearing limit
  - 🔴 Red = exhausted

### Usage Statistics
- **Groups** — number of configured app groups
- **Exhausted** — groups that hit limit today
- **Active** — groups still within limit

---

## Architecture

```
ScreenTimeLock/
├── lib/
│   ├── main.dart                    # Entry point, CupertinoApp, method channel
│   ├── home_screen.dart             # Dashboard with ring + stats + app tiles
│   ├── onboarding_screen.dart       # Permission setup flow
│   ├── settings_screen.dart         # Locked settings (ad/type to unlock)
│   ├── lock_screen_popup.dart       # Non-dismissible lock dialog + bypass
│   ├── screens/
│   │   └── app_picker_screen.dart   # Searchable installed apps list
│   ├── models/
│   │   └── app_group.dart           # Group model (name, packages, limit)
│   ├── services/
│   │   ├── storage_service.dart     # SharedPreferences persistence
│   │   ├── usage_tracker.dart       # Usage stats polling
│   │   ├── app_closure_handler.dart # MethodChannel bridge to native
│   │   ├── ad_reward_system.dart    # Google Mobile Ads integration
│   │   └── message_verification.dart# Typing challenge logic
│   └── utils/
│       └── no_paste_formatter.dart  # Clipboard paste blocker
├── android/
│   └── app/src/main/kotlin/com/example/app_idea/
│       ├── MainActivity.kt          # FlutterActivity + MethodChannel
│       ├── AppClosureHandler.kt     # Force-close / home redirect
│       └── UsageAccessibilityService.kt # Foreground detection + enforcement
└── pubspec.yaml
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Local-only storage** | SharedPreferences — no server, no network calls |
| **Kotlin Accessibility Service** | Real-time foreground app detection |
| **Dart-side usage stats** | `usage_stats` package for dashboard; native re-reads prefs for enforcement |
| **MethodChannel bridge** | `app_closure` channel for Flutter ↔ Android |
| **Cupertino widgets** | iOS-style dark theme, premium feel |
| **Typing challenge** | Forces mindful decision to bypass limits |
| **No re-check on foreground** | Permissions checked once during onboarding |

---

## Permissions

| Permission | Purpose |
|-----------|---------|
| `PACKAGE_USAGE_STATS` | Read app usage for screen time tracking |
| `BIND_ACCESSIBILITY_SERVICE` | Detect blocked app opens & enforce limits |

Both granted manually in system settings. On **OxygenOS/ColorOS**, navigate to:
Settings → Accessibility → Downloaded apps → ScreenTimeLock.

---

## Build & Run

```bash
git clone https://github.com/EGBYtest/APp-idea.git
cd APp-idea
flutter pub get
flutter run
```

> **Note:** Uses Google Mobile Ads **test** unit IDs. Replace before release.

### Requirements
- Flutter SDK ≥ 3.0.0
- Dart SDK ≥ 3.0.0
- Android API 30+ recommended

---

## Tech Stack

- **Framework:** Flutter (Cupertino widgets)
- **Language:** Dart + Kotlin (native)
- **Ads:** Google Mobile Ads SDK (rewarded video)
- **Storage:** SharedPreferences
- **Usage Stats:** `usage_stats` package
- **Build:** Flutter CLI / Gradle

---

## License

All rights reserved.
