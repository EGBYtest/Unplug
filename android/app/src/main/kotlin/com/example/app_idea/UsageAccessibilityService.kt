package com.example.app_idea

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Intent
import android.content.Context
import android.app.ActivityManager
import android.app.usage.UsageStatsManager
import android.util.Log
import org.json.JSONArray
import java.util.Calendar

class UsageAccessibilityService : AccessibilityService() {

    private val TAG = "UsageService"
    private var lastPkg = ""
    private var lastCheck = 0L
    private val blockCount = mutableMapOf<String, LongArray>() // pkg -> [count, firstBlockMs]

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            val type = event?.eventType ?: return
            if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

            val pkg = event.packageName?.toString()?.trim() ?: return
            if (pkg == packageName || pkg.startsWith("com.android.") || pkg.startsWith("com.systemui")) return

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
                                    Log.d(TAG, "global ban (activity): $banName in $pkg")
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
                                Log.d(TAG, "global ban (content match!): $banName in $pkg — keywords=$keywordList")
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
                                    Log.d(TAG, "ban (activity): $banName in $pkg")
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
                                Log.d(TAG, "ban (content match!): $banName in $pkg — keywords=$keywordList")
                                blockApp(pkg, groupName, banName)
                                return
                            }
                        }
                    }
                }
            }

            // Check time limit
            val bonus = prefs.getInt("flutter.bonus_seconds_$groupName", 0)
            val totalLimit = limit + (bonus / 60)
            if (totalLimit == 0) { blockApp(pkg, groupName); return }

            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
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
                Log.d(TAG, "block $pkg ($groupName): ${totalMs/60000}m >= ${totalLimit}m")
                blockApp(pkg, groupName)
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
            Log.d(TAG, "scanForContentKeywords error: ${e.message}")
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

            // Skip entire nav-bar subtree
            if (isNavChild) return false

            for (kw in keywords) {
                // Check view ID resource name — skip clickable/focusable nodes
                // (tabs/buttons) whose IDs happen to contain a keyword.
                if (!isClickable && !isFocusable && nodeViewId.isNotEmpty() && nodeViewId.contains(kw)) {
                    Log.d(TAG, "Matched viewId: '$kw' in '$nodeViewId'")
                    return true
                }

                // Check class name (e.g. com.google.android.apps.youtube.app.extensions.reel...)
                if (nodeClass.isNotEmpty() && nodeClass.contains(kw)) {
                    Log.d(TAG, "Matched className: '$kw' in '$nodeClass'")
                    return true
                }

                // Check text or content description — skip interactive elements
                // and edge-positioned elements (bottom nav labels, action bar titles).
                if (!isClickable && !isFocusable && !isEdgeUi) {
                    if ((nodeText.isNotEmpty() && nodeText.contains(kw)) || (nodeDesc.isNotEmpty() && nodeDesc.contains(kw))) {
                        Log.d(TAG, "Matched text/desc: '$kw' (text='$nodeText', desc='$nodeDesc')")
                        return true
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
        val now = System.currentTimeMillis()

        // Track rapid re-blocks within 5s window
        val entry = blockCount[pkg]
        val count = if (entry != null && now - entry[1] < 5000) entry[0].toInt() + 1 else 1
        blockCount[pkg] = longArrayOf(count.toLong(), if (count == 1) now else entry!![1])
        val aggressive = count >= 3

        if (aggressive) Log.d(TAG, "aggressive block #$count for $pkg")

        // Immediately execute BACK global action to exit the feature/view
        performGlobalAction(GLOBAL_ACTION_BACK)

        if (feature != null) {
            // In-app feature block: only dismiss the feature, keep the app alive
            if (aggressive) {
                // User keeps returning to blocked feature — go home instead
                val home = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(home)
            }
            return
        }

        // Kill app (time-limit block only)
        try {
            val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            try {
                am::class.java.getMethod("forceStopPackage", String::class.java).invoke(am, pkg)
                Log.d(TAG, "forceStop $pkg")
            } catch (_: Exception) {
                am.killBackgroundProcesses(pkg)
                Log.d(TAG, "killBg $pkg")
                try {
                    for (p in (am.runningAppProcesses ?: emptyList())) {
                        if (p.processName == pkg) android.os.Process.killProcess(p.pid)
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}

        if (aggressive) {
            performGlobalAction(GLOBAL_ACTION_RECENTS)
            performGlobalAction(GLOBAL_ACTION_BACK)
            try { Thread.sleep(200) } catch (_: Exception) {}
            val home = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(home)
            try { Thread.sleep(100) } catch (_: Exception) {}
        }

        // Show lock screen
        val i = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("SHOW_LOCK_SCREEN_APP_NAME", group)
        }
        startActivity(i)
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
                val bonus = prefs.getInt("flutter.bonus_seconds_$name", 0)
                if (limit + (bonus / 60) == 0 || getUsageMinutesForGroup(name, p) >= (limit + (bonus / 60))) {
                    blockApp(p, name); return
                }
            }
        } catch (_: Exception) {}
    }

    private fun getUsageMinutesForGroup(group: String, sample: String): Int {
        return try {
            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val cal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            var stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, cal.timeInMillis, System.currentTimeMillis())
            if (stats.isNullOrEmpty()) stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, cal.timeInMillis, System.currentTimeMillis())
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
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
