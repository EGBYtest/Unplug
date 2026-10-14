<p align="center">
  <img src="assets/ic_launcher.png" alt="Unplug" width="120">
</p>

<h1 align="center">Unplug</h1>

<p align="center">
  <strong>Take back your time. One mindful decision at a time.</strong>
</p>

<p align="center">
  <a href="https://github.com/EGBYtest/Unplug/releases/latest">
    <img src="https://img.shields.io/badge/Download-APK-brightgreen?style=for-the-badge&logo=android" alt="Download APK">
  </a>
</p>

<p align="center">
  <strong>Version 2.1.0</strong> · Android 7.0+ · Free · No accounts
</p>

---

## What it does

You have 40 minutes of Instagram a day. Unplug holds you to it.

It does that in a way that doesn't make you uninstall it. When you're out, you get a full-screen lock with two ways through: **wait**, or **write**. Both are deliberately a bit annoying. That's the feature.

The difference from apps like this that you hate: it doesn't delete anything, and it doesn't nuke an app for being open. It blocks the *tab* that actually eats your life — Shorts, Reels, Spotlight — and leaves the rest of the app alone.

**Everything stays on your phone.** No account, no sign-up, no cloud, no analytics. The only thing it ever sends anywhere is a check for whether a newer version exists.

---

## Install it

There's no Play Store listing. Get the APK from the
[releases page](https://github.com/EGBYtest/Unplug/releases/latest) and install it.

- Android 7.0 or newer
- ~49 MB
- You'll need to allow your browser to "install unknown apps"

**Your phone will warn you. That's expected, and it's about the app, not you.** Google Play Protect flags any app it hasn't seen before — Unplug is new and has almost no installs, so it has no reputation with Google. The warning means *"I don't know this app"*, **not** *"I found something bad"*.

If that makes you uneasy, don't install it. That's a reasonable call. But know that the entire app is on [this page](https://github.com/EGBYtest/Unplug) — the Flutter UI in `lib/`, the enforcement code in `android/`, all of it. If you'd rather read it than trust it, that's the better order.

When you open it, it asks for three things. Here's what each one actually does:

| Permission | What Unplug does with it |
|---|---|
| **Usage Access** | Reads how long you've used each app today, so it can count against your limit |
| **Accessibility Service** | Sees which app is in front, and closes the app or drops the lock screen when you're out |
| **Display over other apps** | Draws that lock screen on top of whatever you were using |

Android shows a genuinely alarming warning when you enable an accessibility service — *"can read all screen content and perform actions"*. It shows that exact text for every accessibility app ever made, including screen readers and password managers. Unplug uses it to see which app is open and to press Back. It does not record your screen, read your keystrokes, or send content anywhere. There's no server to send it to.

You can revoke all three, any time, in Android Settings.

**One more, later:** on your first in-app update the phone will offer Unplug permission to *"install unknown apps"*. Unplug asks for that only when you tap an update, never at setup, and uses it for exactly one thing — installing the next version of itself, which you confirm in Android's own installer. It cannot install anything else, and it won't ask again once you've decided.

---

## Setting it up

Make a group, put some apps in it, pick a limit. `0` means blocked immediately — useful for the app you keep saying you'll stop opening.

Then enable the accessibility service. **Unplug does nothing without it.** This is the part most people skip, and then wonder why nothing happens.

<details>
<summary><strong>On OxygenOS, ColorOS, or MIUI</strong></summary>

These manufacturers bury the accessibility list somewhere different, and their battery savers are aggressive about killing it.

- Settings → Accessibility → Downloaded apps → Unplug
- Also add it to your auto-start / battery optimisation allowlist
- If enforcement stops working after a reboot or a nap, this is why
</details>

---

## When you run out

**Wait.** A timer. You choose the length on a **min / sec wheel** — anything from **30 seconds to 3 minutes 59 seconds** — because how much friction you're willing to accept is your call, not the app's. Spin below 30 seconds and it springs back. The timer restarts if you leave the app or shrink the window, so it can't tick away in the background while you're doing something else.

**Or write.** A 50-word challenge, matched exactly. No copy-paste, no "close enough".

Whatever you pick, you get the same thing: a set amount of extra screen time, **starting from wherever you already are**. If you're 50 minutes into a 40-minute limit and you complete a wait worth 5 minutes, you get 55 — not 45, which is still under what you've used and would feel like nothing happened. You don't have to earn your way back to the limit first. Then the bonus is spent, and it's gone.

Both lengths are adjustable, independently. Same payout either way — a longer wait just costs you more.

<details>
<summary><strong>About the wait screen</strong></summary>

It's a plain timer, not an ad. There's no ad SDK in this app and no ad network it talks to. The dialog shows a link to our own shop, [yourwatch.no](https://yourwatch.no), where we sell custom watches. It makes no network requests. If you tap the link, your browser opens and that's the entire interaction.

If that bothers you: it's there because the wait has to be worth something to us, and this was the honest version of that. The alternative was an ad SDK, and we decided that was worse.
</details>

---

## Blocking the tabs, not the apps

This is the part that makes Unplug survivable.

| App | Blocked | Still works |
|---|---|---|
| YouTube | Shorts | Everything else |
| Instagram | Reels | Feed, DMs, stories |
| Snapchat | Spotlight | Camera, chat, map |
| TikTok | For You | Profile, inbox |
| Facebook | Reels & Watch | Feed, groups, messenger |
| Reddit | Popular / Watch / Shorts | Your subreddits |

Unplug exits the tab and leaves you where you were. You came to check a DM; you can still check the DM.

These ship switched off — turn on the ones you actually want blocked, in Settings. You can add your own keywords per app too.

---

## Making settings stick

Limits, groups and blockers all sit behind a lock. Changing one costs the same wait or writing challenge as everything else — including turning the lock off.

It's aimed at the 11pm version of you who is genuinely convinced that "just 5 more minutes" is a reasonable request. It's not security: those values live in ordinary storage on your phone, and someone deliberately trying to get past it on a rooted device can. It stops an impulse, not an attacker. Nothing stops you uninstalling.

---

## Your data

It's on your phone. That's the whole story, but concretely:

- Groups, limits, usage history and bonus time live in local storage on the device
- Enforcement runs entirely on-device and reads those same local values
- **The only things it ever fetches** are the GitHub Releases API and the raw `VERSION` file, to check whether a newer version exists — and, once, the release APK itself when you tap the update banner. Nothing about your usage, your groups, or you is ever in any of those requests.
- No accounts, no analytics, no crash reporting, no tracking

If you don't believe that, it's searchable: grep the repo for `HttpClient`, `http`, and `WebView` and follow every call. There are two files that do network I/O — one checks for a new version, one downloads it — and neither sends anything outward.

---

## Updating

Unplug checks for new versions on its own. When there's one, a blue banner appears on the dashboard.

Tap it and Unplug downloads the APK itself and hands it to Android's installer. You stay in the app, confirm the install, and that's it — no browser, no release page, no hunting through a file manager.

The first time you do this, Android will ask permission for Unplug to install apps. That's the one permission this release adds. Grant it once, from the screen it sends you to, and every later update is a single tap.

If the download fails — bad connection, captive wifi, the release pulled — the banner says so and offers to open the release page in your browser instead. The old way still works; it's just no longer the way.

The banner only shows when there's genuinely something newer, and you can dismiss it. It comes back for the next release.

<details>
<summary><strong>If updates aren't appearing</strong></summary>

- **On v2.0.2 or older:** those builds send you to the browser instead of downloading in-app. Everything still works, it's just the longer route.
- **On v1.1.7 or older:** those builds are missing a permission they need to reach the network at all. They can't detect any update, including the one that fixes it. Download the latest release by hand.
- **On v1.1.9:** also by hand. That release is a pre-release, and pre-releases aren't offered to anyone.
- **Otherwise:** the check is throttled to once every 30 minutes, and a fresh app start always checks straight away. Force-close and reopen, then give it a few seconds.
- Still nothing? `adb logcat -s Unplug: UpdateChecker` prints every HTTP response the checker gets, including rate-limit errors.
</details>

---

## Building it

```bash
git clone https://github.com/EGBYtest/Unplug.git
cd Unplug
flutter pub get
flutter build apk --release
```

Flutter 3.47.7, Gradle 8.14+, AGP 8.11.1+, Kotlin 2.2.20, NDK 28.x. Android minSdk 24.

The version lives in one place, the `version:` line in `pubspec.yaml`; `lib/generated/app_version.dart` is generated from it by `./tool/gen_version.sh`. Everything else follows.

### Layout

```
lib/
├── main.dart                       Entry point, MethodChannel
├── home_screen.dart                Dashboard: ring chart, stats, update banner
├── settings_screen.dart            Locked settings
├── lock_screen_popup.dart          The lock screen and its two ways out
├── generated/app_version.dart      Generated — don't edit
├── services/
│   ├── storage_service.dart        Local storage, bonus and limit maths
│   ├── update_checker.dart         GitHub check, throttle, cache, fallback
│   ├── usage_tracker.dart          Usage stats for the dashboard numbers
│   ├── reward_gate.dart            The wait timer
│   └── message_verification.dart   The writing challenge
└── android/app/src/main/kotlin/com/egbytest/unplug/
    ├── MainActivity.kt             Flutter bridge
    └── UsageAccessibilityService.kt   Foreground watch and enforcement
```

Enforcement lives entirely in the Kotlin service. It reads the same preferences
the Dart side writes, and never asks Dart for anything — which is why it keeps
working while the app is closed.

### Verifying a release

1. The tag and the published `VERSION` file agree.
2. `aapt2 dump badging` on the built APK, to confirm the permissions are
   actually in the binary. Not the source — the binary.
3. Network audit: every outbound request should be in
   `lib/services/update_checker.dart`. There is no ad SDK and no analytics SDK
   to find.

---

## License

All rights reserved.