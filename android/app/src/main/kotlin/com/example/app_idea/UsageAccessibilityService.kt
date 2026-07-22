package com.example.app_idea

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
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
            if (pkg == packageName || pkg.startsWith("com.android.")) return

            // throttle same package to 1s
            val now = System.currentTimeMillis()
            if (pkg == lastPkg && now - lastCheck < 1000) return
            lastPkg = pkg
            lastCheck = now

            checkAndBlock(pkg, event.className?.toString()?.trim())
            enforceVisiblePackages()
        } catch (e: Exception) {
            Log.e(TAG, "event error", e)
        }
    }

    private fun checkAndBlock(pkg: String, className: String?) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
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

            // check banned features first
            if (className != null && g.has("bannedFeatures")) {
                val bans = g.getJSONArray("bannedFeatures")
                for (b in 0 until bans.length()) {
                    val ban = bans.getJSONObject(b)
                    if (ban.has("activityPattern")) {
                        val pattern = ban.getString("activityPattern")
                        if (className.matches(Regex(pattern, RegexOption.IGNORE_CASE))) {
                            Log.d(TAG, "ban: ${ban.getString("name")} in $pkg")
                            blockApp(pkg, groupName, ban.getString("name"))
                            return
                        }
                    }
                }
            }

            // check time limit
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
                    if (s.packageName in listOf(pkg)) { // simplified: just check current pkg
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

    private fun blockApp(pkg: String, group: String, feature: String? = null) {
        val now = System.currentTimeMillis()

        // track rapid re-blocks within 5s window
        val entry = blockCount[pkg]
        val count = if (entry != null && now - entry[1] < 5000) entry[0].toInt() + 1 else 1
        blockCount[pkg] = longArrayOf(count.toLong(), if (count == 1) now else entry!![1])
        val aggressive = count >= 3

        if (aggressive) Log.d(TAG, "aggressive block #$count for $pkg")

        // kill app
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
            // dismiss floating windows before lock screen
            performGlobalAction(GLOBAL_ACTION_BACK)
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

        // show lock screen
        val i = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("SHOW_LOCK_SCREEN_APP_NAME", group)
            if (feature != null) putExtra("SHOW_LOCK_SCREEN_FEATURE_NAME", feature)
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
            for (w in windows) {
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
