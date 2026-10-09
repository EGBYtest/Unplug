package com.example.app_idea

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

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            val type = event?.eventType ?: return
            if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
                type != AccessibilityEvent.TYPE_VIEW_SELECTED &&
                type != AccessibilityEvent.TYPE_VIEW_CLICKED) return

            val pkg = event.packageName?.toString()?.trim() ?: return
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
                        return
                    }
                }
            }

            // Check time limit
            val bonus = prefs.getFlutterInt("flutter.bonus_seconds_$groupName", 0)
            val totalLimit = limit + (bonus / 60)
            if (totalLimit == 0) { blockApp(pkg, groupName); return }

            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val resetHour = prefs.getFlutterInt("flutter.reset_hour", 2)
            val cal = Calendar.getInstance().apply {
                if (get(Calendar.HOUR_OF_DAY) < resetHour) add(Calendar.DAY_OF_MONTH, -1)
                set(Calendar.HOUR_OF_DAY, resetHour); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            var stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, cal.timeInMillis, System.currentTimeMillis())
            if (stats.isNullOrEmpty()) stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, cal.timeInMillis, System.currentTimeMillis())

            var totalMs = 0L
            if (stats != null) {
                for (s in stats) {
                    if (s.packageName in listOf(pkg)) {
                        totalMs += s.totalTimeInForeground
                    }
                }
            }
            if (totalMs / 60000 >= totalLimit) {
                Log.i(TAG, "block $pkg ($groupName): ${totalMs/60000}m >= ${totalLimit}m")
                blockApp(pkg, groupName)
            } else {
                Log.i(TAG, "ok $pkg ($groupName): ${totalMs/60000}m / ${totalLimit}m (bonus=${bonus}s, resetHour=$resetHour)")
            }
            return
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
        val kwJson = ban.optJSONArray("contentKeywords")
        val keywords = if (kwJson != null) {
            (0 until kwJson.length()).mapNotNull {
                kwJson.optString(it, "").trim().lowercase().ifEmpty { null }
            }
        } else emptyList()
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

        // 5) View-hierarchy scan
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
                    val inNavRegion = isPositionedAtScreenEdge(node)
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
            val isEdgeUi = isPositionedAtScreenEdge(node)

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
                    // outside the navigation bars.
                    if (visible && !node.isClickable && !node.isFocusable && !isNav && !isEdgeUi) {
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
     * Returns true if the node is positioned at the top or bottom edge
     * of the screen and is small enough to be a navigation / action-bar
     * element rather than content.
     */
    private fun isPositionedAtScreenEdge(node: AccessibilityNodeInfo): Boolean {
        try {
            val rect = android.graphics.Rect()
            node.getBoundsInScreen(rect)
            val screenHeight = resources.displayMetrics.heightPixels
            val density = resources.displayMetrics.density
            val smallHeight = (120 * density).toInt()
            val atBottom = rect.top > screenHeight * 0.85f && rect.height() < smallHeight
            val atTop = rect.bottom < screenHeight * 0.10f && rect.height() < smallHeight
            return atBottom || atTop
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

    private fun blockApp(pkg: String, group: String, feature: String? = null) {
        // Don't stack overlays or restart the flow while one is active.
        if (overlayActive) return
        val now = System.currentTimeMillis()
        if (now - lastMainLaunch < 1500) return

        val entry = blockCount[pkg]
        val count = if (entry != null && now - entry[1] < 5000) entry[0].toInt() + 1 else 1
        blockCount[pkg] = longArrayOf(count.toLong(), if (count == 1) now else entry!![1])
        val aggressive = count >= 3

        if (aggressive) Log.i(TAG, "aggressive block #$count for $pkg")

        performGlobalAction(GLOBAL_ACTION_BACK)

        if (feature != null) {
            if (aggressive) {
                val home = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(home)
            }
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
            val canOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(this)
            } else true
            if (!canOverlay) {
                launchLockScreenActivity(group, feature, skipCountdown = false)
                return
            }

            removeOverlay()
            overlayGroup = group
            overlayFeature = feature
            overlayCountdown = 5
            overlayActive = true

            val ctx = applicationContext
            val root = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setBackgroundColor(Color.parseColor("#FF0A0A0A"))
                isClickable = true
            }
            root.setOnTouchListener { _, _ -> true }

            val isFeature = feature.isNotEmpty()
            val icon = TextView(ctx).apply {
                text = if (isFeature) "🚫" else "🔒"
                textSize = 44f
                gravity = Gravity.CENTER
            }
            val title = TextView(ctx).apply {
                text = if (isFeature) "In-App Feature Blocked" else "Time Exhausted"
                textSize = 22f
                setTextColor(Color.WHITE)
                setTypeface(null, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            val subtitle = TextView(ctx).apply {
                text = if (isFeature) "Access to \"$feature\" in $group is restricted."
                        else "Your screen time for \"$group\" is up."
                textSize = 15f
                setTextColor(Color.parseColor("#B3B3B3"))
                gravity = Gravity.CENTER
                setPadding(dp(32), dp(8), dp(32), 0)
            }
            val count = TextView(ctx).apply {
                id = 0x1001
                text = "3"
                textSize = 64f
                setTextColor(Color.parseColor("#0A84FF"))
                setTypeface(null, Typeface.BOLD)
                gravity = Gravity.CENTER
            }
            val note = TextView(ctx).apply {
                text = "Take five seconds before deciding\nif you really want more screen time."
                textSize = 13f
                setTextColor(Color.parseColor("#8C8C8C"))
                gravity = Gravity.CENTER
                setPadding(dp(32), dp(12), dp(32), 0)
            }

            root.addView(icon)
            root.addView(title)
            root.addView(subtitle)
            root.addView(count)
            root.addView(note)

            // TYPE_ACCESSIBILITY_OVERLAY is the system-sanctioned window
            // type for overlays drawn by an AccessibilityService. OEM
            // security suites flag ordinary TYPE_APPLICATION_OVERLAY
            // windows combined with accessibility usage as suspicious
            // and may auto-disable the service. Accessibility overlays
            // are explicitly allowed and need no SYSTEM_ALERT_WINDOW.
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
            Log.i(TAG, "countdown overlay shown for $group")

            overlayHandler.removeCallbacks(overlayTick)
            overlayHandler.post(overlayTick)
        } catch (e: Exception) {
            Log.e(TAG, "overlay error", e)
            overlayActive = false
            removeOverlay()
            launchLockScreenActivity(group, feature, skipCountdown = false)
        }
    }

    private val overlayTick = object : Runnable {
        override fun run() {
            if (!overlayActive) return
            if (overlayCountdown > 0) {
                overlayView?.findViewById<TextView>(0x1001)?.text = overlayCountdown.toString()
                overlayCountdown--
                overlayHandler.postDelayed(this, 1000)
            } else {
                removeOverlay()
                launchLockScreenActivity(overlayGroup, overlayFeature ?: "", skipCountdown = true)
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
                val bonus = prefs.getFlutterInt("flutter.bonus_seconds_$name", 0)
                if (limit + (bonus / 60) == 0 || getUsageMinutesForGroup(name, p) >= (limit + (bonus / 60))) {
                    blockApp(p, name); return
                }
            }
        } catch (_: Exception) {}
    }

    private fun getUsageMinutesForGroup(group: String, sample: String): Int {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val resetHour = prefs.getFlutterInt("flutter.reset_hour", 2)
            val cal = Calendar.getInstance().apply {
                if (get(Calendar.HOUR_OF_DAY) < resetHour) add(Calendar.DAY_OF_MONTH, -1)
                set(Calendar.HOUR_OF_DAY, resetHour); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            var stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, cal.timeInMillis, System.currentTimeMillis())
            if (stats.isNullOrEmpty()) stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, cal.timeInMillis, System.currentTimeMillis())
            val json = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            val groups = JSONArray(json)
            val pkgs = mutableListOf<String>()
            for (i in 0 until groups.length()) {
                val g = groups.getJSONObject(i)
                if (g.getString("name") == group) {
                    val a = g.getJSONArray("packageNames")
                    for (j in 0 until a.length()) pkgs.add(a.getString(j).trim())
                }
            }
            var ms = 0L
            for (s in stats) { if (s.packageName in pkgs) ms += s.totalTimeInForeground }
            (ms / 60000).toInt()
        } catch (_: Exception) { 0 }
    }

    override fun onInterrupt() {}
}
