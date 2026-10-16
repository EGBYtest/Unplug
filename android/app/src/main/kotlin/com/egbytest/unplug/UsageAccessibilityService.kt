package com.egbytest.unplug

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Intent
import android.content.Context
import android.app.usage.UsageStatsManager
import android.util.Log
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface

private fun SharedPreferences.getFlutterInt(key: String, default: Int): Int {
    return try {
        val value = all[key] ?: return default
        when (value) {
            is Long -> value.toInt()
            is Int -> value
            else -> default
        }
    } catch (_: Exception) {
        default
    }
}

class UsageAccessibilityService : AccessibilityService() {

    private val TAG = "UsageService"

    /** View id of the countdown digits, so the tick can find them by lookup. */
    private val COUNTDOWN_ID = 0x1001
    private var lastPkg = ""
    private var lastCheck = 0L
    private val blockCount = mutableMapOf<String, LongArray>() // pkg -> [count, firstBlockMs]

    // Full-screen countdown overlay state
    private var overlayView: View? = null
    private var overlayCountdown = 0
    private var overlayActive = false
    private var overlayGroup = ""
    private var overlayFeature: String? = null
    private var lastMainLaunch = 0L
    private val overlayHandler = Handler(Looper.getMainLooper())

    // Which overlay is on screen. blockApp() returns early when one is active
    // so overlays never stack, which is correct for block — but wrong for the
    // two opt-in interstitials, which are not a penalty and must yield to a
    // real block. Without this, a group sitting at its limit would show the
    // open gate on launch and swallow the block that was already owed.
    //   ""          none
    //   "block"     time exhausted / banned feature — unclosable
    //   "gate"      open gate — Open / Go back buttons after the countdown
    //   "reminder"  break reminder — Close button after the countdown
    private var overlayMode = ""

    // ─── Foreground package tracking ─────────────────────────────────────
    //
    // Both opt-in interstitials are about *sessions*, not about the app that
    // happens to be frontmost when an event fires:
    //
    //   the open gate fires when the user *enters* an app, and
    //   the break reminder fires after N minutes of *continuous* use.
    //
    // Neither is derivable from the events for one package alone, because
    // onAccessibilityEvent deliberately discards com.android.* and
    // com.systemui before doing anything. So the transition away from a
    // restricted app to the launcher is invisible unless it is observed here,
    // on the way past that filter. Without this, leaving Instagram and coming
    // back looks like one unbroken session: the gate would never fire a second
    // time, and the reminder would keep counting a session the user had
    // already ended.
    //
    // Only TYPE_WINDOW_STATE_CHANGED counts as a transition. Content-change
    // events from systemui arrive constantly, and treating those as "left the
    // app" would restart the session on every notification shade pull.
    private var lastForegroundPkg = ""

    /** True when this package has already been gated for the current entry. */
    private var gateShownFor = ""

    // ─── Continuous-use session ─────────────────────────────────────────
    //
    // Start of the current uninterrupted sit in one restricted app, used only
    // by the break reminder. Reset on a foreground transition away, and
    // re-validated when the reminder fires rather than trusted blindly: the
    // session can end without any event reaching this service at all (screen
    // off, app killed from recents), and the reminder must not fire over a
    // session that ended ten minutes ago.
    private val breakHandler = Handler(Looper.getMainLooper())
    private var breakSessionPkg = ""
    private var breakSessionStart = 0L
    private var breakMinutes = 10
    private var breakFiredThisSession = false

    /** Milliseconds. Guards against a zero/garbage persisted value. */
    private fun breakThresholdMs(): Long =
        breakMinutes.coerceIn(1, 60) * 60_000L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            val type = event?.eventType ?: return
            if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
                type != AccessibilityEvent.TYPE_VIEW_SELECTED &&
                type != AccessibilityEvent.TYPE_VIEW_CLICKED &&
                type != AccessibilityEvent.TYPE_VIEW_SCROLLED) return

            val pkg = event.packageName?.toString()?.trim() ?: return

            // Observed before the self/system filter, because "the user left
            // the restricted app" is exactly the transition this filter hides.
            if (type == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && pkg != packageName) {
                // Our own overlay is an accessibility overlay owned by this
                // service, so adding and removing it produces window state
                // changes under our own package name. Counting those as the
                // foreground changing would clear gateShownFor the moment the
                // gate went up, so it would immediately re-arm over itself.
                onForegroundChanged(pkg)
            }

            if (pkg == packageName || pkg.startsWith("com.android.") || pkg.startsWith("com.systemui")) return

            Log.i(TAG, "event: $pkg (type=$type)")

            // Tab activation events (selected/clicked) bypass the
            // throttle — they are the strongest detection signal and
            // must never be dropped by the 200ms content-change filter.
            val isTap = type == AccessibilityEvent.TYPE_VIEW_SELECTED ||
                        type == AccessibilityEvent.TYPE_VIEW_CLICKED
            val now = System.currentTimeMillis()
            if (!isTap && pkg == lastPkg && now - lastCheck < 200) return
            lastPkg = pkg
            lastCheck = now

            val source = event.source
            checkAndBlock(pkg, event.className?.toString()?.trim(), source, event.text, isTap)
            source?.recycle()
            enforceVisiblePackages()
        } catch (e: Exception) {
            Log.e(TAG, "event error", e)
        }
    }

    private fun checkAndBlock(
        pkg: String,
        className: String?,
        sourceNode: AccessibilityNodeInfo?,
        windowTitle: List<CharSequence>?,
        tapEvent: Boolean,
    ) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // 1) Standalone Global In-App Tab Blockers (independent of App Groups)
        val globalBlockersJson = prefs.getString("flutter.global_tab_blockers", "[]") ?: "[]"
        if (globalBlockersJson != "[]") {
            try {
                val blockers = JSONArray(globalBlockersJson)
                for (b in 0 until blockers.length()) {
                    val ban = blockers.getJSONObject(b)
                    if (ban.has("isEnabled") && !ban.getBoolean("isEnabled")) continue

                    val banPkg = ban.optString("packageName", "").trim()
                    if (banPkg.isNotEmpty() && banPkg != pkg) continue

                    val banName = ban.getString("name")
                    if (detectFeature(pkg, ban, className, windowTitle, sourceNode, tapEvent)) {
                        Log.i(TAG, "global ban: $banName in $pkg")
                        blockApp(pkg, "In-App Feature", banName)
                        scheduleFeatureRecheck(pkg, keywordsOf(ban), "In-App Feature", banName)
                        return
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "global tab blockers error", e)
            }
        }

        // 2) Check App Group Time Limits
        val json = prefs.getString("flutter.app_groups", "[]") ?: "[]"
        if (json == "[]") return

        val groups = JSONArray(json)
        for (i in 0 until groups.length()) {
            val g = groups.getJSONObject(i)
            val pkgs = g.getJSONArray("packageNames")
            var match = false
            for (j in 0 until pkgs.length()) {
                if (pkgs.getString(j).trim() == pkg) { match = true; break }
            }
            if (!match) continue

            val groupName = g.getString("name")
            val limit = g.getInt("timeLimitMinutes")

            // Check banned features first
            if (g.has("bannedFeatures")) {
                val bans = g.getJSONArray("bannedFeatures")
                for (b in 0 until bans.length()) {
                    val ban = bans.getJSONObject(b)
                    if (ban.has("isEnabled") && !ban.getBoolean("isEnabled")) continue
                    if (ban.has("packageName")) {
                        val banPkg = ban.getString("packageName").trim()
                        if (banPkg.isNotEmpty() && banPkg != pkg) continue
                    }

                    val banName = ban.getString("name")
                    if (detectFeature(pkg, ban, className, windowTitle, sourceNode, tapEvent)) {
                        Log.i(TAG, "ban (feature): $banName in $pkg ($groupName)")
                        blockApp(pkg, groupName, banName)
                        scheduleFeatureRecheck(pkg, keywordsOf(ban), groupName, banName)
                        return
                    }
                }
            }

            // Check time limit
            val usedMinutes = groupUsageMinutes(groupName, prefs)
            val totalLimit = effectiveLimitMinutes(groupName, limit, usedMinutes, prefs)
            if (totalLimit == 0) { blockApp(pkg, groupName); return }

            if (usedMinutes >= totalLimit) {
                Log.i(TAG, "block $pkg ($groupName): ${usedMinutes}m >= ${totalLimit}m")
                blockApp(pkg, groupName)
            } else {
                Log.i(TAG, "ok $pkg ($groupName): ${usedMinutes}m / ${totalLimit}m (bonus=${bonusSecondsFor(groupName, prefs)}s, resetHour=${prefs.getFlutterInt("flutter.reset_hour", 2)})")
                armDeadline(groupName, limit, usedMinutes, totalLimit)
                // Only meaningful while the user is inside the app and under
                // limit; the reminder is about a sit that is still going.
                trackBreakSession(pkg, g)
            }
            return
        }
    }

    // ─── Bonus time ─────────────────────────────────────────────────────
    //
    // The bonus key is scoped to the day it was earned on:
    //   flutter.bonus_seconds_<group>_<YYYY-MM-DD>
    //   flutter.bonus_anchor_<group>_<YYYY-MM-DD>
    //
    // This service reads SharedPreferences directly and never runs Dart. An
    // unscoped key was only ever cleared by Dart running — at app launch or on
    // the next read — so a user who did not open Unplug across the reset hour
    // kept yesterday's bonus in force here, while the dashboard (which did
    // check) showed zero. Day-scoping the key makes a stale balance simply
    // not exist for either reader, with no dependence on the app running.
    //
    // The anchor is the usage reading at grant time. Credit granted is
    // anchored to it, and usage since then is subtracted to find what is
    // left. Storing the anchor rather than decrementing a stored balance is
    // deliberate: consumption stays a pure read, so the balance is correct
    // even for a user who never opens the app between two enforcement checks.
    //
    // The key formats are cross-language contracts; StorageService._bonusKey
    // and StorageService._bonusAnchorKey build the same strings. Keep in step.
    private fun bonusSecondsFor(groupName: String, prefs: SharedPreferences): Int {
        return prefs.getFlutterInt(bonusKey(groupName, dayStart(prefs)), 0)
    }

    /** Usage reading captured when credit was granted, or null if there is none. */
    private fun bonusAnchorOrNull(groupName: String, prefs: SharedPreferences): Int? {
        val day = dayStart(prefs)
        val key = bonusAnchorKey(groupName, day)
        if (!prefs.contains(key)) return null
        return prefs.getFlutterInt(key, 0)
    }

    private fun bonusKey(groupName: String, day: Calendar): String =
        String.format(
            "flutter.bonus_seconds_%s_%04d-%02d-%02d",
            groupName, day.get(Calendar.YEAR), day.get(Calendar.MONTH) + 1,
            day.get(Calendar.DAY_OF_MONTH),
        )

    private fun bonusAnchorKey(groupName: String, day: Calendar): String =
        String.format(
            "flutter.bonus_anchor_%s_%04d-%02d-%02d",
            groupName, day.get(Calendar.YEAR), day.get(Calendar.MONTH) + 1,
            day.get(Calendar.DAY_OF_MONTH),
        )

    /**
     * Ceiling in minutes: the higher of the limit and the credit budget.
     *
     * Credit reaches (usage at grant) + (everything granted) — a fixed budget,
     * not a balance to subtract from the limit. Subtracting spent credit would
     * shrink the ceiling as the user spends it, so the instant they started
     * using the bonus they would drop below it again. Spending must move usage
     * up towards a target, not the target down towards usage.
     *
     * So a user at 50m against a 40m limit who earns 5m gets 55m — the five
     * they chose. Adding the granted total to the limit gave 45m instead, still
     * under their usage, so the bonus appeared to do nothing.
     *
     * Mirrors StorageService.effectiveLimitMinutes. Both sides must agree or
     * the dashboard and the limiter disagree about whether the user is in.
     *
     * Pure reads — nothing writes on consumption, so this stays correct for a
     * user who never opens the app between two checks.
     */
    private fun effectiveLimitMinutes(
        groupName: String,
        limit: Int,
        usedMinutes: Int,
        prefs: SharedPreferences,
    ): Int {
        if (limit == 0) return 0
        val granted = bonusSecondsFor(groupName, prefs)
        if (granted <= 0) return limit
        val anchor = bonusAnchorOrNull(groupName, prefs)
        // No anchor: a grant written before this model existed. Fall back to the
        // additive ceiling rather than dividing by a zero anchor, which would
        // silently confiscate bonus the user had already paid for.
        if (anchor == null) return limit + granted / 60
        val creditCeiling = (anchor * 60 + granted) / 60
        return if (creditCeiling > limit) creditCeiling else limit
    }

    /** Start of the current usage day — midnight of the reset hour. */
    private fun dayStart(prefs: SharedPreferences): Calendar {
        val resetHour = prefs.getFlutterInt("flutter.reset_hour", 2)
        return Calendar.getInstance().apply {
            if (get(Calendar.HOUR_OF_DAY) < resetHour) add(Calendar.DAY_OF_MONTH, -1)
            set(Calendar.HOUR_OF_DAY, resetHour); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
    }

    // ─── Usage accounting ────────────────────────────────────────────────
    //
    // One definition of "how much has this group used today", shared by the
    // per-event check in checkAndBlock and the sweep in enforceVisiblePackages.
    //
    // These used to disagree. checkAndBlock summed only the foreground
    // package while comparing against the GROUP limit, so a "Social Media =
    // 30 minutes across 5 apps" budget was enforced on that path as 30
    // minutes in any single app. enforceVisiblePackages summed the whole
    // group and got it right, and ran immediately afterwards on the same
    // event, so the stricter reading won in practice — but one path would log
    // "ok" right before the other blocked. Two answers to one question is a
    // trap for whoever edits this next.

    /**
     * Foreground minutes used by every package in [groupName] since the last
     * reset hour. Returns 0 when usage access is unavailable.
     */
    private fun groupUsageMinutes(groupName: String, prefs: SharedPreferences): Int {
        return try {
            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = dayStart(prefs)
            var stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, cal.timeInMillis, System.currentTimeMillis())
            if (stats.isNullOrEmpty()) stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, cal.timeInMillis, System.currentTimeMillis())

            val packages = packageNamesForGroup(groupName, prefs)
            var ms = 0L
            if (stats != null) {
                for (s in stats) {
                    if (s.packageName in packages) ms += s.totalTimeInForeground
                }
            }
            (ms / 60000).toInt()
        } catch (_: Exception) {
            0
        }
    }

    /** The package list configured for [groupName], or empty if no such group. */
    private fun packageNamesForGroup(groupName: String, prefs: SharedPreferences): List<String> {
        return try {
            val json = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (json == "[]") return emptyList()
            val groups = JSONArray(json)
            val out = mutableListOf<String>()
            for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                if (g.getString("name") == groupName) {
                    val a = g.getJSONArray("packageNames")
                    for (j in 0 until a.length()) out.add(a.getString(j).trim())
                }
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    // ─── In-app feature detection ─────────────────────────────────────────
    //
    // Multi-signal detector for short-form content tabs (Snapchat
    // Spotlight, YouTube Shorts, Instagram Reels, ...). Signals,
    // strongest first:
    //
    // 1. Tap events — TYPE_VIEW_SELECTED / TYPE_VIEW_CLICKED deliver
    //    the exact view the user just activated. No guessing needed.
    // 2. Activity / class-name regex (activityPattern from config).
    // 3. Window title of the event — many apps title the screen after
    //    the active tab.
    // 4. Titles of all visible accessibility windows.
    // 5. View-hierarchy scan — selected-tab state (with ancestor
    //    propagation), feature-specific class names, resource IDs and
    //    visible non-navigation text.

    private fun detectFeature(
        pkg: String,
        ban: JSONObject,
        className: String?,
        windowTitle: List<CharSequence>?,
        sourceNode: AccessibilityNodeInfo?,
        tapEvent: Boolean,
    ): Boolean {
        val keywords = keywordsOf(ban)
        val pattern = ban.optString("activityPattern", "").trim()
        if (keywords.isEmpty() && pattern.isEmpty()) return false

        // 1) Tap fast path — the view that was just selected / clicked
        if (tapEvent && sourceNode != null) {
            if (nodeMatchesFeature(sourceNode, keywords, forTap = true, depth = 0)) return true
        }

        // 2) Activity / class-name pattern
        if (className != null && pattern.isNotEmpty()) {
            try {
                if (className.matches(Regex(pattern, RegexOption.IGNORE_CASE))) return true
            } catch (_: Exception) {}
        }

        // 3) Event window title
        if (titleMatches(windowTitle, keywords)) return true

        // 4) Titles of all visible windows
        try {
            val windowList = windows ?: emptyList()
            for (w in windowList) {
                val title = w.title?.toString()?.lowercase() ?: continue
                if (keywords.any { title.contains(it) }) {
                    Log.i(TAG, "Matched window title: '$title'")
                    return true
                }
            }
        } catch (_: Exception) {}

        // 5) Changed-subtree fast path — the view that fired
        //    the event is often the newly visible page itself
        //    (swipes, fragment swaps, pager transitions).
        if (sourceNode != null) {
            if (scanNodeTree(sourceNode, keywords)) return true
        }

        // 6) Full view-hierarchy scan
        return scanVisibleTrees(pkg, keywords)
    }

    /**
     * Extracts the (lowercased) content keywords from a
     * blocker config object.
     */
    private fun keywordsOf(ban: JSONObject): List<String> {
        val kwJson = ban.optJSONArray("contentKeywords")
        return if (kwJson != null) {
            (0 until kwJson.length()).mapNotNull {
                kwJson.optString(it, "").trim().lowercase().ifEmpty { null }
            }
        } else emptyList()
    }

    /**
     * Scans the active window and all visible windows that
     * belong to the given package for the feature keywords.
     */
    private fun scanVisibleTrees(pkg: String, keywords: List<String>): Boolean {
        try {
            val activeRoot = rootInActiveWindow
            if (activeRoot != null) {
                val rootPkg = activeRoot.packageName?.toString()?.trim() ?: ""
                if (rootPkg == pkg || rootPkg.isEmpty()) {
                    val found = scanNodeTree(activeRoot, keywords)
                    activeRoot.recycle()
                    if (found) return true
                } else {
                    activeRoot.recycle()
                }
            }
            val windowList = windows ?: emptyList()
            for (w in windowList) {
                val root = w.root ?: continue
                val rootPkg = root.packageName?.toString()?.trim() ?: continue
                if (rootPkg != pkg) { root.recycle(); continue }
                val found = scanNodeTree(root, keywords)
                root.recycle()
                if (found) return true
            }
        } catch (e: Exception) {
            Log.i(TAG, "tree scan error: ${e.message}")
        }
        return false
    }

    // ─── Post-transition recheck ───────────────────────────────
    //
    // A single BACK press can lose the race with a page
    // transition (tab click / swipe) — the blocked tab
    // sometimes still opens. After every feature block we
    // re-scan the visible trees ~400ms later, once the
    // transition has settled, and press BACK again if the
    // blocked feature is still showing. Repeated a couple of
    // times for slow transitions. The app is never closed —
    // only the back button is used.

    private val recheckHandler = Handler(Looper.getMainLooper())
    private var recheckAttempts = 0
    private var recheckPkg = ""
    private var recheckGroup = ""
    private var recheckFeature = ""
    private var recheckKeywords: List<String>? = null

    // ─── Limit deadline ───────────────────────────────────────────
    //
    // Enforcement otherwise only ever runs when an accessibility
    // event arrives, so a user who sits still with a restricted app
    // open is never checked: they stay in the app past the limit and
    // are released only when they next touch the screen, which can be
    // minutes later. This arms a single one-shot re-check for the
    // moment the remaining time is up, so the block lands on the
    // clock instead of on the next tap. The check reuses
    // enforceVisiblePackages(), which already sweeps visible windows
    // and escalates through blockApp().
    //
    // This is a deadline, not a poll — one usage query per remaining
    // window — so it costs nothing measurable in battery. Every
    // passing check re-arms it from the fresh reading, so a changed
    // limit or bonus credit moves the deadline with it.
    //
    // It deliberately does not use recheckHandler: that one is torn
    // down wholesale on every feature block, which would silently
    // cancel an armed limit deadline.

    private val deadlineHandler = Handler(Looper.getMainLooper())
    private var deadlineGroup = ""
    private var deadlineLimit = 0
    private var deadlineLogKey = ""

    private fun armDeadline(group: String, limit: Int, usedMinutes: Int, totalLimit: Int) {
        val remainingSec = (totalLimit - usedMinutes) * 60L
        deadlineHandler.removeCallbacks(deadlineCheck)
        if (remainingSec <= 0L) return
        deadlineGroup = group
        deadlineLimit = limit
        // Handler delays are MILLISECONDS. Passing seconds here once armed a
        // 17-minute deadline at 1020ms, which turned this into a self
        // re-arming once-a-second loop on the main looper — the same looper
        // accessibility events are delivered on. The service spent its life
        // doing a synchronous usage query per second and stopped enforcing
        // anything, and because the loop re-armed itself, no amount of leaving
        // the app helped. Observed on device: "deadline armed ... in 17m"
        // repeating once every 1.025s until the process was restarted.
        val delayMs = remainingSec * 1000L
        // Floor and ceiling are belt and braces. Nothing about a limit change
        // should be able to turn this into a hot loop again, and a re-arm
        // that lands every few seconds is indistinguishable from the bug
        // above when you are the one reading the logs.
        val safeDelayMs = delayMs.coerceIn(30_000L, 6L * 60L * 60L * 1000L)
        deadlineHandler.postDelayed(deadlineCheck, safeDelayMs)
        // Only log when the deadline actually moves. armDeadline runs on every
        // accessibility event, so logging unconditionally puts two lines per
        // event into logcat from the hottest path in the app.
        if (deadlineLogKey != "$group/$safeDelayMs") {
            deadlineLogKey = "$group/$safeDelayMs"
            Log.i(TAG, "deadline armed for $group in ${remainingSec / 60}m ($usedMinutes/$totalLimit)")
        }
    }

    private val deadlineCheck = object : Runnable {
        override fun run() {
            val group = deadlineGroup
            if (group.isEmpty()) return
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val used = groupUsageMinutes(group, prefs)
                val total = effectiveLimitMinutes(group, deadlineLimit, used, prefs)
                if (total == 0 || used >= total) {
                    Log.i(TAG, "deadline hit for $group: ${used}m >= ${total}m — sweeping visible windows")
                    enforceVisiblePackages()
                } else {
                    // Android's counter can still trail reality, so the
                    // limit may not have crossed yet. Re-arm rather than
                    // giving up, or the user walks past the deadline.
                    Log.i(TAG, "deadline early for $group: ${used}m / ${total}m — re-arming")
                    armDeadline(group, deadlineLimit, used, total)
                }
            } catch (e: Exception) {
                Log.e(TAG, "deadline check failed", e)
            }
        }
    }

    private fun scheduleFeatureRecheck(pkg: String, keywords: List<String>, group: String, feature: String) {
        recheckHandler.removeCallbacksAndMessages(null)
        recheckAttempts = 0
        recheckPkg = pkg
        recheckGroup = group
        recheckFeature = feature
        recheckKeywords = keywords
        recheckHandler.postDelayed(featureRecheck, 400)
    }

    private val featureRecheck = object : Runnable {
        override fun run() {
            val keywords = recheckKeywords
            if (keywords.isNullOrEmpty()) return
            try {
                if (scanVisibleTrees(recheckPkg, keywords)) {
                    Log.i(TAG, "recheck #$recheckAttempts: still on $recheckFeature — backing out")
                    blockApp(recheckPkg, recheckGroup, recheckFeature)
                    if (recheckAttempts < 2) {
                        recheckAttempts++
                        recheckHandler.postDelayed(this, 400)
                    }
                }
            } catch (_: Exception) {}
        }
    }

    /**
     * Matches a single node (the view that was just selected or
     * clicked) against the feature keywords.
     *
     * Structural identifiers (view ID resource name, class name) are
     * developer-defined and unique to the feature, so they always
     * match. Text / description only match inside navigation regions
     * (screen edges) or on selected nodes — tapping an ordinary
     * "Watch this!" link in the middle of content must not trigger a
     * block.
     */
    private fun nodeMatchesFeature(
        node: AccessibilityNodeInfo,
        keywords: List<String>,
        forTap: Boolean,
        depth: Int,
    ): Boolean {
        if (depth > 5) return false
        try {
            val viewId = node.viewIdResourceName?.toString()?.lowercase() ?: ""
            val cls = node.className?.toString()?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""

            for (kw in keywords) {
                if (viewId.contains(kw) || cls.contains(kw)) return true
                if (text.contains(kw) || desc.contains(kw)) {
                    val inNavRegion = isPositionedAtScreenTop(node) ||
                            isPositionedAtScreenBottom(node)
                    if (!forTap || inNavRegion || node.isSelected || hasSelectedAncestor(node)) {
                        Log.i(TAG, "Matched tap node text: '$kw'")
                        return true
                    }
                }
            }

            val count = node.childCount
            for (i in 0 until count) {
                val child = node.getChild(i) ?: continue
                val found = nodeMatchesFeature(child, keywords, forTap, depth + 1)
                child.recycle()
                if (found) return true
            }
        } catch (_: Exception) {}
        return false
    }

    private fun titleMatches(windowTitle: List<CharSequence>?, keywords: List<String>): Boolean {
        if (windowTitle.isNullOrEmpty() || keywords.isEmpty()) return false
        val title = windowTitle.joinToString(" ").toString().lowercase()
        if (title.isEmpty()) return false
        return keywords.any { title.contains(it) }
    }

    /**
     * Recursively scans the view hierarchy for the feature.
     *
     * A node counts as the active feature when:
     * - it or any ancestor is SELECTED — tab bars set selection on the
     *   tab container while the label lives on a child view, so the
     *   selected state must propagate down the tree (Snapchat's
     *   Spotlight tab is exactly this shape), or
     * - its class name references the feature (reel / shorts player
     *   classes) and it is visible on screen, or
     * - its resource ID matches on a non-interactive node, or
     * - its text matches on a visible, non-interactive node outside
     *   the navigation bars.
     *
     * Unselected navigation labels and off-screen (ViewPager-preloaded)
     * nodes are ignored so the rest of the app stays usable.
     */
    private fun scanNodeTree(node: AccessibilityNodeInfo?, keywords: List<String>, depth: Int = 0): Boolean {
        if (node == null || depth > 30 || keywords.isEmpty()) return false

        try {
            val nodeText = node.text?.toString()?.lowercase() ?: ""
            val nodeDesc = node.contentDescription?.toString()?.lowercase() ?: ""
            val nodeViewId = node.viewIdResourceName?.toString()?.lowercase() ?: ""
            val nodeClass = node.className?.toString()?.lowercase() ?: ""

            val selected = node.isSelected || hasSelectedAncestor(node)
            val visible = node.isVisibleToUser
            val isNav = isNavBarDescendant(node)
            val atBottom = isPositionedAtScreenBottom(node)

            if (selected) {
                // Active tab / feature — match everything on it.
                for (kw in keywords) {
                    if (nodeViewId.contains(kw) || nodeClass.contains(kw) ||
                        nodeText.contains(kw) || nodeDesc.contains(kw)) {
                        Log.i(TAG, "Matched selected node: '$kw'")
                        return true
                    }
                }
            } else {
                for (kw in keywords) {
                    // Top-edge screen title (e.g. Snapchat's "Spotlight!"
                    // header) names the current feature directly. It must
                    // match even when the node is clickable/focusable or
                    // wrapped in a toolbar/action-bar container — those
                    // properties are common on header labels and cannot
                    // be trusted to exclude it.
                    if (visible && isPositionedAtScreenTop(node) &&
                        (nodeText.contains(kw) || nodeDesc.contains(kw))) {
                        Log.i(TAG, "Matched top title text: '$kw'")
                        return true
                    }
                    // Feature-specific player classes only exist while
                    // the feature is on screen.
                    if (visible && nodeClass.isNotEmpty() && nodeClass.contains(kw)) {
                        Log.i(TAG, "Matched className: '$kw' in '$nodeClass'")
                        return true
                    }
                    // Resource IDs on non-interactive nodes (containers,
                    // labels) are stable feature identifiers.
                    if (visible && !node.isClickable && !node.isFocusable &&
                        nodeViewId.isNotEmpty() && nodeViewId.contains(kw)) {
                        Log.i(TAG, "Matched viewId: '$kw' in '$nodeViewId'")
                        return true
                    }
                    // Plain text only when visible, non-interactive and
                    // outside the bottom navigation bar. Top-edge
                    // titles name the current screen (e.g. Snapchat's
                    // "Spotlight" header) and are a strong signal, so
                    // they are matched; bottom-edge nav labels are
                    // present on every screen and only count when
                    // selected.
                    if (visible && !node.isClickable && !node.isFocusable && !isNav && !atBottom) {
                        if (nodeText.contains(kw) || nodeDesc.contains(kw)) {
                            Log.i(TAG, "Matched text/desc: '$kw'")
                            return true
                        }
                    }
                }
            }

            val count = node.childCount
            for (i in 0 until count) {
                val child = node.getChild(i) ?: continue
                val found = scanNodeTree(child, keywords, depth + 1)
                child.recycle()
                if (found) return true
            }
        } catch (_: Exception) {}

        return false
    }

    /**
     * Returns true if any ancestor of the node is selected.
     * Tab bars typically set selection on the tab container (the
     * clickable item) while the label text lives on a child view that
     * is not selected itself — e.g. Snapchat's "Spotlight" tab.
     */
    private fun hasSelectedAncestor(node: AccessibilityNodeInfo): Boolean {
        var current = try { node.parent } catch (_: Exception) { null }
        var levels = 0
        while (current != null && levels < 8) {
            val selected = current.isSelected
            val next = try { current.parent } catch (_: Exception) { null }
            current.recycle()
            if (selected) return true
            current = next
            levels++
        }
        return false
    }

    /**
     * Returns true if the node is a small element in the top
     * 15% of the screen — an action-bar / header title that
     * names the current screen (e.g. Snapchat's "Spotlight!"
     * label). Keyword-gated, so widening the band cannot cause
     * false positives on other screens.
     */
    private fun isPositionedAtScreenTop(node: AccessibilityNodeInfo): Boolean {
        try {
            val rect = android.graphics.Rect()
            node.getBoundsInScreen(rect)
            val screenHeight = resources.displayMetrics.heightPixels
            val density = resources.displayMetrics.density
            val smallHeight = (160 * density).toInt()
            return rect.bottom < screenHeight * 0.15f && rect.height() < smallHeight
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Returns true if the node is a small element in the bottom
     * 15% of the screen — a bottom-nav label. These are present
     * on every screen of the app, so their text only counts as
     * a feature signal when selected.
     */
    private fun isPositionedAtScreenBottom(node: AccessibilityNodeInfo): Boolean {
        try {
            val rect = android.graphics.Rect()
            node.getBoundsInScreen(rect)
            val screenHeight = resources.displayMetrics.heightPixels
            val density = resources.displayMetrics.density
            val smallHeight = (120 * density).toInt()
            return rect.top > screenHeight * 0.85f && rect.height() < smallHeight
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Returns true if the node is a descendant of a navigation bar,
     * toolbar, or tab container — meaning its text/desc likely
     * represents a nav label rather than content.
     */
    private fun isNavBarDescendant(node: AccessibilityNodeInfo): Boolean {
        val navClassPatterns = listOf(
            "bottomnavigation", "navigationbar", "navigationrail",
            "tabwidget", "tablayout", "tabbar", "tabrow",
            "actionbar", "toolbar"
        )

        // Check node's own class
        val ownClass = node.className?.toString()?.lowercase() ?: ""
        for (pat in navClassPatterns) {
            if (ownClass.contains(pat)) return true
        }

        // Walk up ancestors (up to 5 levels) in case nav bar is wrapped
        // inside intermediate containers or custom view hierarchies.
        var current = try { node.parent } catch (_: Exception) { null }
        var levels = 0
        while (current != null && levels < 5) {
            val parentClass = current.className?.toString()?.lowercase() ?: ""
            for (pat in navClassPatterns) {
                if (parentClass.contains(pat)) {
                    current.recycle()
                    return true
                }
            }
            val next = try { current.parent } catch (_: Exception) { null }
            current.recycle()
            current = next
            levels++
        }
        current?.recycle()

        return false
    }

    // ─── Foreground sessions, open gate, break reminder ───────────────
    //
    // Two opt-in interstitials, both per-group, both off by default:
    //
    //  1. Open gate — every time the user enters one of the group's apps,
    //     a short countdown runs with no way through, and only after it
    //     finishes do "Open X" and "Go back" appear. Tapping Open does
    //     nothing to the app: it was already launched, the overlay was
    //     only ever a question asked on top of it.
    //
    //  2. Break reminder — after the group has been used continuously for
    //     the configured number of minutes, ask whether the sit was meant
    //     to be this long. It does not close anything and does not dismiss
    //     itself; it waits for a Close tap.
    //
    // Neither is a penalty and neither reduces the remaining time, which is
    // why they are allowed to yield to a real block below: a user who is
    // already over their limit must get the block, not a nicer version of it.
    //
    // Group config keys are read with optBoolean rather than getBoolean, so
    // an install whose stored groups predate these fields loads as "off"
    // instead of throwing inside the event handler.

    /** The group owning [pkg], or null. Also the lookup both features share. */
    private fun groupFor(pkg: String, groups: JSONArray): JSONObject? {
        for (i in 0 until groups.length()) {
            val g = groups.getJSONObject(i)
            val pkgs = g.optJSONArray("packageNames") ?: continue
            for (j in 0 until pkgs.length()) {
                if (pkgs.optString(j).trim() == pkg) return g
            }
        }
        return null
    }

    private fun appLabel(pkg: String): String {
        return try {
            val pm = packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) {
            pkg.substringAfterLast('.')
        }
    }

    /**
     * A restricted app lost or gained the foreground. Ends the previous
     * continuous-use session and, on entering one, offers the open gate.
     */
    private fun onForegroundChanged(pkg: String) {
        if (pkg == lastForegroundPkg) return
        val previous = lastForegroundPkg
        lastForegroundPkg = pkg

        // Leaving a restricted app ends its session. Not conditional on the
        // group having the reminder on: a session that stopped counting when
        // the setting was switched off mid-sit must not resume counting as if
        // it had run continuously.
        if (breakSessionPkg.isNotEmpty() && breakSessionPkg != pkg) {
            endBreakSession("left for $pkg")
        }

        // A new entry may be gated again, but only if this package is not the
        // one already behind the gate — otherwise showing the gate is itself
        // enough to look like a foreground change and it would re-arm.
        if (pkg != gateShownFor) gateShownFor = ""

        // Walking away from the gate closes it rather than leaving an
        // unclosable overlay over the launcher.
        if (overlayMode == "gate" && overlayGroup != pkg) {
            removeOverlay()
        }

        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val json = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (json == "[]") return
            val group = groupFor(pkg, JSONArray(json)) ?: return

            // Never gate a package the user is already over the limit on. The
            // block is the correct response there and it is about to arrive;
            // a gate in front of it would swallow the entry that triggers it.
            val name = group.optString("name", "")
            val used = groupUsageMinutes(name, prefs)
            val total = effectiveLimitMinutes(name, group.optInt("timeLimitMinutes", 0), used, prefs)
            if (total == 0 || used >= total) return

            if (group.optBoolean("openGateEnabled", false)) {
                showOpenGate(pkg, name)
            }
        } catch (e: Exception) {
            Log.e(TAG, "foreground change error", e)
        }
    }

    // ─── Continuous-use session (break reminder) ────────────────────────

    /** Called from the under-limit branch of checkAndBlock, on every event. */
    private fun trackBreakSession(pkg: String, group: JSONObject) {
        if (!group.optBoolean("breakReminderEnabled", false)) {
            if (breakSessionPkg == pkg) endBreakSession("group setting off")
            return
        }
        breakMinutes = group.optInt(
            "breakReminderMinutes",
            10,
        ).coerceIn(1, 60)

        val now = System.currentTimeMillis()
        if (breakSessionPkg != pkg) {
            breakHandler.removeCallbacks(breakCheck)
            breakSessionPkg = pkg
            breakSessionStart = now
            breakFiredThisSession = false
        }

        // One arm per session. Re-arming on every event is what turned the
        // limit deadline into a once-a-second loop in v2.0.2; the session timer
        // is short enough that the bug would be just as visible here.
        if (breakFiredThisSession) return
        if (breakHandler.hasCallbacks(breakCheck)) return

        val elapsed = now - breakSessionStart
        val remaining = breakThresholdMs() - elapsed
        if (remaining <= 0L) {
            breakCheck.run()
            return
        }
        breakHandler.postDelayed(breakCheck, remaining)
        Log.i(TAG, "break reminder armed for $pkg in ${breakMinutes}m")
    }

    private fun endBreakSession(reason: String) {
        if (breakSessionPkg.isEmpty()) return
        breakHandler.removeCallbacks(breakCheck)
        Log.i(TAG, "break session ended for $breakSessionPkg ($reason)")
        breakSessionPkg = ""
        breakSessionStart = 0L
        breakFiredThisSession = false
    }

    private val breakCheck = object : Runnable {
        override fun run() {
            val pkg = breakSessionPkg
            if (pkg.isEmpty()) return
            try {
                // The session can end with no event reaching this service at
                // all — screen off, or killed from recents — so "is it still
                // going" is answered by asking the window list, not by assuming
                // the timer was right.
                if (pkg != lastForegroundPkg || !isVisible(pkg)) {
                    endBreakSession("no longer in foreground")
                    return
                }
                breakFiredThisSession = true
                Log.i(TAG, "break reminder for $pkg after ${breakMinutes}m continuous")
                showBreakOverlay(pkg)
            } catch (e: Exception) {
                Log.e(TAG, "break check failed", e)
            }
        }
    }

    /** Whether [pkg] still has a window on screen. Cheap; used by both timers. */
    private fun isVisible(pkg: String): Boolean {
        return try {
            val list = windows ?: return false
            for (w in list) {
                if (w.root?.packageName?.toString()?.trim() == pkg) return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun blockApp(pkg: String, group: String, feature: String? = null) {
        // A real block always wins over the opt-in interstitials — they are
        // questions, not consequences. Only a block defers to another block.
        if (overlayActive) {
            if (overlayMode == "block") return
            removeOverlay()
        }
        val now = System.currentTimeMillis()
        if (now - lastMainLaunch < 1500) return

        val entry = blockCount[pkg]
        val count = if (entry != null && now - entry[1] < 5000) entry[0].toInt() + 1 else 1
        blockCount[pkg] = longArrayOf(count.toLong(), if (count == 1) now else entry!![1])
        val aggressive = count >= 3

        if (aggressive) Log.i(TAG, "aggressive block #$count for $pkg")

        performGlobalAction(GLOBAL_ACTION_BACK)

        if (feature != null) {
            // In-app feature blocks only ever use the back
            // button — the app itself is never closed.
            return
        }

        val hasOverlay = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else true

        if (!hasOverlay) {
            performGlobalAction(GLOBAL_ACTION_HOME)
        }

        if (aggressive) {
            performGlobalAction(GLOBAL_ACTION_RECENTS)
            performGlobalAction(GLOBAL_ACTION_BACK)
        }

        // Full-screen OS overlay with an unclosable countdown. When the
        // countdown finishes the Flutter lock screen is launched as an
        // overlay-typed window so it covers whatever app is beneath.
        showCountdownOverlay(group, feature ?: "")
    }

    /**
     * Adds a full-screen, touch-blocking overlay window with a countdown.
     * Back is consumed while it is visible; the overlay itself cannot be
     * dismissed because it sits above every app and the launcher. When the
     * countdown finishes the Flutter lock screen is launched with the
     * countdown skipped.
     */
    private fun showCountdownOverlay(group: String, feature: String) {
        try {
            val ctx = applicationContext
            val root = overlayRoot(ctx)
            overlayGroup = group
            overlayFeature = feature
            overlayMode = "block"

            val isFeature = feature.isNotEmpty()
            root.addView(overlayText(ctx, if (isFeature) "🚫" else "🔒", 44f, Color.WHITE, bold = false))
            root.addView(overlayText(ctx, if (isFeature) "In-App Feature Blocked" else "Time Exhausted", 22f, Color.WHITE, bold = true))
            root.addView(overlayText(ctx, if (isFeature) "Access to \"$feature\" in $group is restricted."
                    else "Your screen time for \"$group\" is up.", 15f, Color.parseColor("#B3B3B3"), padTop = 8))
            root.addView(overlayCountdown(ctx))
            root.addView(overlayText(ctx, "Take five seconds before deciding\nif you really want more screen time.", 13f, Color.parseColor("#8C8C8C"), padTop = 12))

            startOverlay(root, "block")
            Log.i(TAG, "countdown overlay shown for $group")
        } catch (e: Exception) {
            Log.e(TAG, "overlay error", e)
            removeOverlay()
            launchLockScreenActivity(group, feature, skipCountdown = false)
        }
    }

    /**
     * The open gate: every entry into a gated package waits here first. The app
     * is already running behind the window — nothing has been closed or paused
     * on its behalf — so "Open" is simply removing the overlay, and "Go back"
     * is removing it and pressing back out of the app.
     */
    private fun showOpenGate(pkg: String, group: String) {
        // Already inside this gate for this entry, or mid-block: nothing to do.
        if (overlayActive) return
        if (gateShownFor == pkg) return
        // Entering the app is what puts the gate up; putting it up must not
        // read as another entry, or it re-arms forever.
        gateShownFor = pkg
        try {
            val ctx = applicationContext
            val root = overlayRoot(ctx)
            val label = appLabel(pkg)
            overlayGroup = pkg
            overlayMode = "gate"

            root.addView(overlayText(ctx, "⏳", 44f, Color.WHITE))
            root.addView(overlayText(ctx, "Opening $label", 22f, Color.WHITE, bold = true))
            root.addView(overlayText(ctx, "Did you really intend to open $label?", 15f, Color.parseColor("#B3B3B3"), padTop = 8))
            root.addView(overlayCountdown(ctx))
            root.addView(overlayText(ctx, "Nothing has been opened yet.", 13f, Color.parseColor("#8C8C8C"), padTop = 12))

            // Buttons start invisible. An always-visible button would be a way
            // through the pause, and the pause is the entire feature.
            val choices = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                visibility = View.GONE
                setPadding(dp(32), dp(24), dp(32), dp(32))
            }
            choices.addView(overlayButton(ctx, "Open $label", true) {
                Log.i(TAG, "gate passed for $pkg")
                removeOverlay()
            })
            choices.addView(overlayButton(ctx, "Go back", false) {
                Log.i(TAG, "gate declined for $pkg")
                removeOverlay()
                performGlobalAction(GLOBAL_ACTION_BACK)
            })
            root.addView(choices)

            startOverlay(root, "gate")
            // Only meaningful if the overlay actually went up; startOverlay
            // nulls this and returns early when drawing is not permitted.
            if (overlayActive) overlayChoices = choices
            Log.i(TAG, "open gate shown for $pkg ($group)")
        } catch (e: Exception) {
            // A gate that cannot be shown must not trap the user in front of an
            // app they cannot get into: fall through and let the app open.
            Log.e(TAG, "open gate error", e)
            gateShownFor = ""
            removeOverlay()
        }
    }

    /**
     * The break reminder. Unlike the block overlay this one never dismisses
     * itself — it waits for a tap, which is the point of asking.
     */
    private fun showBreakOverlay(pkg: String) {
        if (overlayActive) return
        try {
            val ctx = applicationContext
            val root = overlayRoot(ctx)
            val label = appLabel(pkg)
            overlayGroup = pkg
            overlayMode = "reminder"

            root.addView(overlayText(ctx, "🧘", 44f, Color.WHITE))
            root.addView(overlayText(ctx, "$breakMinutes minutes straight", 22f, Color.WHITE, bold = true))
            root.addView(overlayText(ctx, "You have been in $label for $breakMinutes minutes.", 15f, Color.parseColor("#B3B3B3"), padTop = 8))
            root.addView(overlayCountdown(ctx))
            root.addView(overlayText(ctx, "Was this meant to be a long sit,\nor a quick check?", 13f, Color.parseColor("#8C8C8C"), padTop = 12))

            val choices = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                visibility = View.GONE
                setPadding(dp(32), dp(24), dp(32), dp(32))
            }
            choices.addView(overlayButton(ctx, "Close", true) {
                Log.i(TAG, "break reminder closed for $pkg")
                removeOverlay()
            })
            root.addView(choices)

            startOverlay(root, "reminder")
            if (overlayActive) overlayChoices = choices
            Log.i(TAG, "break overlay shown for $pkg")
        } catch (e: Exception) {
            Log.e(TAG, "break overlay error", e)
            removeOverlay()
        }
    }

    // ─── Overlay plumbing, shared by all three overlays ───────────────────

    /** Hidden until the countdown finishes; revealed by [overlayTick]. */
    private var overlayChoices: View? = null

    private fun overlayRoot(ctx: Context): LinearLayout = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setBackgroundColor(Color.parseColor("#FF0A0A0A"))
        isClickable = true
        // Touches are consumed so the app underneath cannot be driven while a
        // question is on screen. The buttons are children of this view, so
        // they still receive their own clicks.
        setOnTouchListener { _, _ -> true }
    }

    private fun overlayText(
        ctx: Context,
        text: String,
        size: Float,
        color: Int,
        bold: Boolean = false,
        padTop: Int = 0,
    ): TextView = TextView(ctx).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        if (bold) setTypeface(null, Typeface.BOLD)
        gravity = Gravity.CENTER
        if (padTop > 0) setPadding(dp(32), dp(padTop), dp(32), 0)
    }

    private fun overlayCountdown(ctx: Context): TextView = TextView(ctx).apply {
        id = COUNTDOWN_ID
        text = "5"
        textSize = 64f
        setTextColor(Color.parseColor("#0A84FF"))
        setTypeface(null, Typeface.BOLD)
        gravity = Gravity.CENTER
    }

    private fun overlayButton(ctx: Context, label: String, primary: Boolean, onTap: () -> Unit): TextView =
        TextView(ctx).apply {
            text = label
            textSize = 16f
            setTextColor(if (primary) Color.WHITE else Color.parseColor("#B3B3B3"))
            setTypeface(null, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(14), dp(24), dp(14))
            val bg = if (primary) Color.parseColor("#0A84FF") else Color.parseColor("#1C1C1E")
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                cornerRadius = dp(12).toFloat()
                setColor(bg)
                setStroke(dp(1), Color.parseColor("#3A3A3C"))
            }
            setOnClickListener { onTap() }
        }

    /**
     * Adds [root] over everything and starts the 5→1 countdown.
     *
     * [mode] is a parameter rather than read from [overlayMode] because this
     * calls removeOverlay(), which clears the field: a mode set by the caller
     * beforehand would be wiped here and the overlay would come up with no
     * idea what it is.
     */
    private fun startOverlay(root: View, mode: String) {
        if (!canDrawOverlay()) {
            // Only the block overlay has a Flutter fallback worth taking; the
            // two interstitials are questions, and the honest answer to a
            // question that cannot be displayed is not to ask it.
            val wasBlock = mode == "block"
            val group = overlayGroup
            val feature = overlayFeature ?: ""
            removeOverlay()
            if (wasBlock) launchLockScreenActivity(group, feature, skipCountdown = false)
            return
        }

        removeOverlay()
        overlayMode = mode
        overlayCountdown = 5
        overlayActive = true
        overlayChoices = null

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.OPAQUE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            params.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        wm.addView(root, params)
        overlayView = root

        overlayHandler.removeCallbacks(overlayTick)
        overlayHandler.post(overlayTick)
    }

    private fun canDrawOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private val overlayTick = object : Runnable {
        override fun run() {
            if (!overlayActive) return
            if (overlayCountdown > 0) {
                overlayView?.findViewById<TextView>(COUNTDOWN_ID)?.text = overlayCountdown.toString()
                overlayCountdown--
                overlayHandler.postDelayed(this, 1000)
                return
            }
            when (overlayMode) {
                "block" -> {
                    removeOverlay()
                    launchLockScreenActivity(overlayGroup, overlayFeature ?: "", skipCountdown = true)
                }
                // Gate and reminder both stop here and wait for a tap. The
                // countdown ending is not permission to dismiss them.
                else -> {
                    overlayView?.findViewById<TextView>(COUNTDOWN_ID)?.visibility = View.GONE
                    overlayChoices?.visibility = View.VISIBLE
                }
            }
        }
    }

    private fun removeOverlay() {
        try {
            val view = overlayView
            if (view != null) {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                wm.removeView(view)
            }
        } catch (_: Exception) {}
        overlayView = null
        overlayActive = false
        overlayChoices = null
        overlayMode = ""
        overlayHandler.removeCallbacks(overlayTick)
    }

    private fun launchLockScreenActivity(group: String, feature: String, skipCountdown: Boolean) {
        lastMainLaunch = System.currentTimeMillis()
        val i = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("SHOW_LOCK_SCREEN_APP_NAME", group)
            putExtra("SHOW_LOCK_SCREEN_FEATURE_NAME", feature)
            putExtra("SHOW_LOCK_SCREEN_SKIP_COUNTDOWN", skipCountdown)
        }
        startActivity(i)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (overlayActive) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK, KeyEvent.KEYCODE_HOME -> return true
            }
        }
        return super.onKeyEvent(event)
    }

    override fun onDestroy() {
        recheckHandler.removeCallbacksAndMessages(null)
        deadlineHandler.removeCallbacksAndMessages(null)
        breakHandler.removeCallbacksAndMessages(null)
        // Leave nothing on screen that the user cannot dismiss: a gate or a
        // reminder has no Flutter fallback and no auto-dismiss, so a view
        // surviving service death would be an overlay they cannot get rid of.
        removeOverlay()
        super.onDestroy()
    }

    private fun enforceVisiblePackages() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val json = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (json == "[]") return
            val groups = JSONArray(json)
            val pkgToGroup = mutableMapOf<String, Pair<String, Int>>()
            for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                val pkgs = g.getJSONArray("packageNames")
                for (j in 0 until pkgs.length()) {
                    pkgToGroup[pkgs.getString(j).trim()] = Pair(g.getString("name"), g.getInt("timeLimitMinutes"))
                }
            }
            val windowList = windows ?: emptyList()
            for (w in windowList) {
                val root = w.root ?: continue
                val p = root.packageName?.toString()?.trim() ?: continue
                val pair = pkgToGroup[p] ?: continue
                val (name, limit) = pair
                val used = groupUsageMinutes(name, prefs)
                val totalLimit = effectiveLimitMinutes(name, limit, used, prefs)
                if (totalLimit == 0 || used >= totalLimit) {
                    blockApp(p, name); return
                }
            }
        } catch (_: Exception) {}
    }

    override fun onInterrupt() {}
}
