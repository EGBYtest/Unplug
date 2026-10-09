package com.example.app_idea

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Intent
import android.content.Context
import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.util.Log
import android.content.SharedPreferences
import org.json.JSONArray
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
            if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

            val pkg = event.packageName?.toString()?.trim() ?: return
            if (pkg == packageName || pkg.startsWith("com.android.") || pkg.startsWith("com.systemui")) return

            Log.i(TAG, "event: $pkg")


            // Throttle events per package to 200ms for smooth performance without missing tab/content changes
            val now = System.currentTimeMillis()
            if (pkg == lastPkg && now - lastCheck < 200) return
            lastPkg = pkg
            lastCheck = now

            checkAndBlock(pkg, event.className?.toString()?.trim(), event.source)
            enforceVisiblePackages()
        } catch (e: Exception) {
            Log.e(TAG, "event error", e)
        }
    }

    private fun checkAndBlock(pkg: String, className: String?, sourceNode: AccessibilityNodeInfo?) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        // 1) Check Standalone Global In-App Tab Blockers first (independent of App Groups)
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

                    // Activity pattern regex match
                    if (className != null && ban.has("activityPattern")) {
                        val pattern = ban.getString("activityPattern")
                        if (pattern.isNotEmpty()) {
                            try {
                                if (className.matches(Regex(pattern, RegexOption.IGNORE_CASE))) {
                                    Log.i(TAG, "global ban (activity): $banName in $pkg")
                                    blockApp(pkg, "In-App Feature", banName)
                                    return
                                }
                            } catch (_: Exception) {}
                        }
                    }

                    // Content keyword match across view hierarchy
                    if (ban.has("contentKeywords")) {
                        val keywords = ban.getJSONArray("contentKeywords")
                        if (keywords.length() > 0) {
                            val keywordList = mutableListOf<String>()
                            for (k in 0 until keywords.length()) {
                                val kw = keywords.getString(k).trim().lowercase()
                                if (kw.isNotEmpty()) keywordList.add(kw)
                            }

                            if (keywordList.isNotEmpty() && scanForContentKeywords(pkg, keywordList)) {
                                Log.i(TAG, "global ban (content match!): $banName in $pkg — keywords=$keywordList")
                                blockApp(pkg, "In-App Feature", banName)
                                return
                            }
                        }
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

                    // 1) Activity pattern regex match
                    if (className != null && ban.has("activityPattern")) {
                        val pattern = ban.getString("activityPattern")
                        if (pattern.isNotEmpty()) {
                            try {
                                if (className.matches(Regex(pattern, RegexOption.IGNORE_CASE))) {
                                    Log.i(TAG, "ban (activity): $banName in $pkg")
                                    blockApp(pkg, groupName, banName)
                                    return
                                }
                            } catch (_: Exception) {}
                        }
                    }

                    // 2) Content keyword match across view hierarchy
                    if (ban.has("contentKeywords")) {
                        val keywords = ban.getJSONArray("contentKeywords")
                        if (keywords.length() > 0) {
                            val keywordList = mutableListOf<String>()
                            for (k in 0 until keywords.length()) {
                                val kw = keywords.getString(k).trim().lowercase()
                                if (kw.isNotEmpty()) keywordList.add(kw)
                            }

                            if (keywordList.isNotEmpty() && scanForContentKeywords(pkg, keywordList)) {
                                Log.i(TAG, "ban (content match!): $banName in $pkg — keywords=$keywordList")
                                blockApp(pkg, groupName, banName)
                                return
                            }
                        }
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

    /**
     * Scans the accessibility node tree for content keywords.
     * Searches rootInActiveWindow first, then visible windows.
     */
    private fun scanForContentKeywords(pkg: String, keywords: List<String>): Boolean {
        try {
            // 1. Try rootInActiveWindow
            val activeRoot = rootInActiveWindow
            if (activeRoot != null) {
                val rootPkg = activeRoot.packageName?.toString()?.trim() ?: ""
                if (rootPkg == pkg || rootPkg.isEmpty()) {
                    if (scanNodeTree(activeRoot, keywords)) return true
                }
            }

            // 2. Try window tree fallback
            val windowList = windows ?: emptyList()
            for (w in windowList) {
                val root = w.root ?: continue
                val rootPkg = root.packageName?.toString()?.trim() ?: continue
                if (rootPkg == pkg) {
                    if (scanNodeTree(root, keywords)) return true
                }
            }
        } catch (e: Exception) {
            Log.i(TAG, "scanForContentKeywords error: ${e.message}")
        }
        return false
    }

    /**
     * Recursively inspects nodes for keyword matches in text, contentDescription,
     * viewIdResourceName, or className.
     * Skips text/desc matching on navigation-bar child nodes to avoid blocking
     * entire apps when tab labels happen to contain a keyword (e.g. "spotlight").
     */
    private fun scanNodeTree(node: AccessibilityNodeInfo?, keywords: List<String>, depth: Int = 0): Boolean {
        if (node == null || depth > 25) return false

        try {
            val nodeText = node.text?.toString()?.lowercase() ?: ""
            val nodeDesc = node.contentDescription?.toString()?.lowercase() ?: ""
            val nodeViewId = node.viewIdResourceName?.toString()?.lowercase() ?: ""
            val nodeClass = node.className?.toString()?.lowercase() ?: ""

            val isNavChild = isNavBarDescendant(node)
            val isClickable = node.isClickable
            val isFocusable = node.isFocusable
            val isEdgeUi = isPositionedAtScreenEdge(node)
            val isSelected = node.isSelected

            // Skip entire nav-bar subtree (unless the nav item itself is the
            // selected/active tab — a selected tab means the user is currently
            // on that feature, e.g. Snapchat's "Spotlight" tab).
            if (isNavChild && !isSelected) return false

            for (kw in keywords) {
                // Selected node: the user is actively on this feature, so match
                // text/desc/viewId without the interactive-element skips. This
                // catches labeled nav tabs (Snapchat Spotlight) and selected
                // toolbar items that the conservative rules would otherwise miss.
                if (isSelected) {
                    if (nodeViewId.isNotEmpty() && nodeViewId.contains(kw)) {
                        Log.i(TAG, "Matched selected viewId: '$kw' in '$nodeViewId'")
                        return true
                    }
                    if (nodeClass.isNotEmpty() && nodeClass.contains(kw)) {
                        Log.i(TAG, "Matched selected className: '$kw' in '$nodeClass'")
                        return true
                    }
                    if ((nodeText.isNotEmpty() && nodeText.contains(kw)) || (nodeDesc.isNotEmpty() && nodeDesc.contains(kw))) {
                        Log.i(TAG, "Matched selected text/desc: '$kw' (text='$nodeText', desc='$nodeDesc')")
                        return true
                    }
                    // No match on this selected node — keep scanning its children.
                } else {
                    // Check view ID resource name — skip clickable/focusable nodes
                    // (tabs/buttons) whose IDs happen to contain a keyword.
                    if (!isClickable && !isFocusable && nodeViewId.isNotEmpty() && nodeViewId.contains(kw)) {
                        Log.i(TAG, "Matched viewId: '$kw' in '$nodeViewId'")
                        return true
                    }

                    // Check class name (e.g. com.google.android.apps.youtube.app.extensions.reel...)
                    if (nodeClass.isNotEmpty() && nodeClass.contains(kw)) {
                        Log.i(TAG, "Matched className: '$kw' in '$nodeClass'")
                        return true
                    }

                    // Check text or content description — skip interactive elements
                    // and edge-positioned elements (bottom nav labels, action bar titles).
                    if (!isClickable && !isFocusable && !isEdgeUi) {
                        if ((nodeText.isNotEmpty() && nodeText.contains(kw)) || (nodeDesc.isNotEmpty() && nodeDesc.contains(kw))) {
                            Log.i(TAG, "Matched text/desc: '$kw' (text='$nodeText', desc='$nodeDesc')")
                            return true
                        }
                    }
                }
            }

            // Recurse into children
            val count = node.childCount
            for (i in 0 until count) {
                val child = node.getChild(i) ?: continue
                if (scanNodeTree(child, keywords, depth + 1)) return true
            }
        } catch (_: Exception) {}

        return false
    }

    /**
     * Returns true if the node is positioned at the top or bottom edge
     * of the screen and is small enough to be a navigation / action-bar element
     * rather than content.
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
     * Returns true if the node is a descendant of a navigation bar, toolbar,
     * or tab container — meaning its text/desc likely represents a nav label
     * rather than content.
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

        // Full-screen OS overlay with an unclosable 3s countdown. After the
        // countdown the Flutter lock screen (options) is shown as an
        // overlay-typed window so it covers whatever app is beneath.
        showCountdownOverlay(group, feature ?: "")
    }

    /**
     * Adds a full-screen, touch-blocking overlay window (SYSTEM_ALERT_WINDOW)
     * with a 3-2-1 countdown. Back is consumed while it is visible; the overlay
     * itself cannot be dismissed because it sits above every app and the
     * launcher. When the countdown finishes the Flutter lock screen is
     * launched with the countdown skipped.
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
            // security suites (OxygenOS "suspicious app activity",
            // MIUI, Samsung) flag ordinary TYPE_APPLICATION_OVERLAY
            // windows combined with accessibility usage as suspicious
            // and may auto-disable the service. Accessibility overlays
            // are explicitly allowed and do not require the
            // SYSTEM_ALERT_WINDOW permission.
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
