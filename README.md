# Unplug

<p align="center">
  <img src="assets/ic_launcher.png" alt="Unplug" width="120">
</p>

<p align="center">
  <strong>Take back your time. One mindful decision at a time.</strong>
</p>

<p align="center">
  <a href="https://github.com/EGBYtest/Unplug/releases/latest">
    <img src="https://img.shields.io/badge/Download-APK-brightgreen?style=for-the-badge&logo=android" alt="Download APK">
  </a>
</p>

---

## What is Unplug?

Unplug helps you reduce mindless scrolling by setting **daily time limits** on app groups and **blocking addictive tabs** like YouTube Shorts, Instagram Reels, and Snapchat Spotlight — without killing the entire app.

When your time runs out, you face a choice: watch a full ad or type a 50-word mindfulness message to earn extra time. No easy skips. No "just 5 more minutes" loopholes.

> **100% local. No accounts. No servers. Your data never leaves your device.**

---

## Why Unplug?

### Set Boundaries That Stick
- Create app groups (Social Media, Games, Entertainment...)
- Set a daily limit per group — 30 minutes, 1 hour, or **0 = block immediately**
- Once exhausted, a full-screen lock appears. No way around it.

### Block Addictive Tabs, Not Apps
| App | Blocked Tab | Rest of App |
|-----|-------------|-------------|
| YouTube | Shorts | Subscriptions, search, normal videos |
| Instagram | Reels | Feed, DMs, stories |
| Snapchat | Spotlight | Camera, chat, map |
| Facebook | Reels & Watch | Feed, groups, messenger |
| TikTok | For You / Following feed | Profile, inbox |
| Reddit | Popular / Watch | Subreddits, comments |

Smart detection exits only the blocked tab. The app stays open.

### Earn More Time — Mindfully
| Method | Bonus | The Catch |
|--------|-------|------------|
| Watch a rewarded ad | +1 min (configurable) | Must watch 30 seconds minimum |
| Type a 50-word challenge | +1 min | Exact match required. No copy-paste. |

Both are intentionally inconvenient — that's the point. If you really need more time, you'll do it. If not, you'll put the phone down.

### Settings That Can't Be Undone on Impulse
- Editing limits, groups, or tab blockers requires completing the same ad-or-type challenge
- Toggle Settings Lock on/off in Settings → Security
- Prevents the "I'll just add 5 more minutes..." spiral

### See Your Progress
- **Circular ring chart** — total screen time vs. your limit, at a glance
- **Weekly average comparison** — are you trending up or down?
- **Per-group progress bars** — green (safe), yellow (near limit), red (exhausted)
- **Bonus time tracking** — see how much extra time you've earned

---

## Screenshots

<p align="center">
  <em>Dashboard · Lock Screen · Settings · Tab Blockers · Onboarding</em>
</p>

---

## Permissions Required

| Permission | Why |
|-----------|-----|
| **Usage Access** | Read how long you've used each app today |
| **Accessibility Service** | Detect when time-limited apps open and enforce limits |

Both are granted manually in Android Settings. Unplug cannot modify these — only you can.

**OxygenOS / ColorOS users:**
Settings → Accessibility → Downloaded apps → Unplug

---

## Download

**[Download the latest APK](https://github.com/EGBYtest/Unplug/releases/latest)** from GitHub Releases.

Requirements:
- Android 11+ (API 30)
- ~24 MB download

> **Note:** Not available on Google Play. Side-loading required — enable "Install unknown apps" for your browser or file manager.

---

## How It Works

Unplug runs an **Android Accessibility Service** that watches which app is in the foreground in real-time. When a time-limited app opens:

1. **Check time** — reads today's usage from Android's built-in UsageStats
2. **Check tab** — scans the view hierarchy for banned in-app features (Shorts, Reels, Spotlight...)
3. **Enforce** — if time is up or tab is blocked, presses BACK to exit the feature. If time limit hit, force-closes the app.
4. **Show lock screen** — full-screen popup with ad and typing challenge options

Everything runs on-device. SharedPreferences stores your groups, limits, and bonus time. The native Kotlin service reads these directly — no network calls during enforcement.

---

## For Developers

### Build

```bash
git clone https://github.com/EGBYtest/Unplug.git
cd Unplug
flutter pub get
flutter build apk --release
```

### Tech Stack

| Layer | Tech |
|-------|------|
| UI Framework | Flutter (Cupertino widgets, dark theme) |
| Frontend Language | Dart |
| Native Enforcement | Kotlin (AccessibilityService) |
| Ads | Google Mobile Ads SDK (rewarded video) |
| Storage | SharedPreferences |
| Usage Tracking | `usage_stats` package |
| Bridge | MethodChannel (Flutter ↔ Android) |

### Architecture

```
Unplug/
├── lib/
│   ├── main.dart                       # Entry point, CupertinoApp, method channel
│   ├── home_screen.dart                # Dashboard with ring chart + stats
│   ├── onboarding_screen.dart          # Permission setup flow
│   ├── settings_screen.dart            # Locked settings (ad/type to unlock)
│   ├── lock_screen_popup.dart          # Non-dismissible lock dialog + bypass
│   ├── screens/
│   │   └── app_picker_screen.dart      # Searchable installed apps list
│   ├── models/
│   │   └── app_group.dart              # AppGroup + BannedFeature models
│   ├── services/
│   │   ├── storage_service.dart        # SharedPreferences persistence
│   │   ├── usage_tracker.dart          # Usage stats polling
│   │   ├── app_closure_handler.dart    # MethodChannel bridge
│   │   ├── ad_reward_system.dart       # Rewarded ad integration
│   │   └── message_verification.dart   # Typing challenge logic
│   └── utils/
│       └── no_paste_formatter.dart     # Clipboard paste blocker
└── android/
    └── app/src/main/kotlin/com/example/app_idea/
        ├── MainActivity.kt             # FlutterActivity + MethodChannel
        ├── AppClosureHandler.kt        # Force-close / home redirect
        └── UsageAccessibilityService.kt # Foreground watch + enforcement + tab blocking
```

### Requirements
- Flutter SDK ≥ 3.0.0
- Dart SDK ≥ 3.0.0
- Android API 30+

---

## Privacy

- No analytics. No tracking. No accounts.
- All data (groups, limits, usage history) stored locally in SharedPreferences
- The install counter (counterapi.dev) fires **once** on first launch with no identifying information
- Source code is open — verify for yourself

---

## License

All rights reserved.
