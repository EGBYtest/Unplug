package com.example.app_idea

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.content.Intent
import android.content.Context
import android.util.Log
import android.app.usage.UsageStatsManager
import android.app.ActivityManager
import org.json.JSONArray
import java.util.Calendar

class UsageAccessibilityService : AccessibilityService() {

    private val TAG = "UsageService"

    // Throttle
    private var lastCheckedPackage: String = ""
    private var lastCheckTime: Long = 0L
    private var lastBlockTime: Long = 0L
    private var lastFeatureBanTime: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val type = event?.eventType ?: return

        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

        val activePackage = event.packageName?.toString()?.trim() ?: return

        val ignoredPackages = setOf(
            packageName,
            "com.android.systemui",
            "com.android.launcher",
            "com.android.launcher3",
            "com.google.android.apps.nexuslauncher",
            "com.miui.home",
            "com.sec.android.app.launcher"
        )
        if (ignoredPackages.contains(activePackage)) return

        val now = System.currentTimeMillis()
        if (activePackage == lastCheckedPackage) {
            if (now - lastCheckTime < 1000) return
        } else {
            lastCheckedPackage = activePackage
        }
        lastCheckTime = now

        Log.d(TAG, "Checking package: $activePackage")

        // 1. Feature ban check — uses rootInActiveWindow UI tree inspection
        //    Only runs every 2s to avoid stutter
        if (now - lastFeatureBanTime > 2000) {
            lastFeatureBanTime = now
            checkFeatureBans(activePackage)
        }

        // 2. Time-limit enforcement (existing flow)
        checkAndEnforceLimits(activePackage)

        enforceVisiblePackages()
    }

    // ── Feature Ban Detection ──────────────────────────────────────────────
    // Uses rootInActiveWindow to inspect the UI tree for banned features.
    // On match: performGlobalAction(GLOBAL_ACTION_BACK) to bounce user out.

    private fun checkFeatureBans(activePackage: String) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (groupsJsonStr == "[]") return

            val groupsArray = JSONArray(groupsJsonStr)

            // Find the group containing this package AND has banned features
            for (i in 0 until groupsArray.length()) {
                val groupObj = groupsArray.getJSONObject(i)
                val pkgsArray = groupObj.getJSONArray("packageNames")

                var packageInGroup = false
                for (j in 0 until pkgsArray.length()) {
                    if (pkgsArray.getString(j).trim() == activePackage) {
                        packageInGroup = true
                        break
                    }
                }
                if (!packageInGroup) continue
                if (!groupObj.has("bannedFeatures")) continue

                val bansArray = groupObj.getJSONArray("bannedFeatures")
                if (bansArray.length() == 0) continue

                // Get the UI tree root
                val root = rootInActiveWindow ?: return

                var nodeCount = 0
                val maxNodes = 100

                fun traverse(node: AccessibilityNodeInfo?): Boolean {
                    if (node == null || nodeCount > maxNodes) return false
                    nodeCount++

                    val rid = node.viewIdResourceName
                    val desc = node.contentDescription?.toString()
                    val text = node.text?.toString()

                    // Check each ban's patterns against this node
                    for (b in 0 until bansArray.length()) {
                        val ban = bansArray.getJSONObject(b)
                        val featureName = ban.getString("name")

                        // Check resource ID patterns
                        if (rid != null && ban.has("resourceIdPatterns")) {
                            val patterns = ban.getJSONArray("resourceIdPatterns")
                            for (p in 0 until patterns.length()) {
                                val pattern = patterns.getString(p)
                                if (rid.contains(pattern, ignoreCase = true)) {
                                    Log.d(TAG, "Banned feature: $featureName (resourceId: $rid matches $pattern)")
                                    node.recycle()
                                    performGlobalAction(GLOBAL_ACTION_BACK)
                                    return true
                                }
                            }
                        }

                        // Check content description patterns
                        if (desc != null && ban.has("descriptionPatterns")) {
                            val patterns = ban.getJSONArray("descriptionPatterns")
                            for (p in 0 until patterns.length()) {
                                val pattern = patterns.getString(p)
                                if (desc.contains(pattern, ignoreCase = true)) {
                                    Log.d(TAG, "Banned feature: $featureName (desc: $desc matches $pattern)")
                                    node.recycle()
                                    performGlobalAction(GLOBAL_ACTION_BACK)
                                    return true
                                }
                            }
                        }

                        // Check visible text patterns
                        if (text != null && ban.has("screenTextPatterns")) {
                            val patterns = ban.getJSONArray("screenTextPatterns")
                            for (p in 0 until patterns.length()) {
                                val pattern = patterns.getString(p)
                                if (text.contains(pattern, ignoreCase = true)) {
                                    Log.d(TAG, "Banned feature: $featureName (text: $text matches $pattern)")
                                    node.recycle()
                                    performGlobalAction(GLOBAL_ACTION_BACK)
                                    return true
                                }
                            }
                        }
                    }

                    // Recurse children (stop early if we find a match)
                    for (c in 0 until node.childCount) {
                        val child = node.getChild(c)
                        if (traverse(child)) {
                            if (node !== root) node.recycle()
                            return true
                        }
                    }

                    if (node !== root) node.recycle()
                    return false
                }

                traverse(root)
                return // Only check first matching group
            }
        } catch (e: Exception) {
            Log.e(TAG, "Feature ban check error", e)
        }
    }

    // ── Time-Limit Enforcement ────────────────────────────────────────────

    private fun checkAndEnforceLimits(activePackage: String) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (groupsJsonStr == "[]") return

            val groupsArray = JSONArray(groupsJsonStr)
            var matchedGroupName: String? = null
            var timeLimitMinutes = 0
            val packagesInGroup = mutableListOf<String>()

            for (i in 0 until groupsArray.length()) {
                val groupObj = groupsArray.getJSONObject(i)
                val pkgsArray = groupObj.getJSONArray("packageNames")
                val currentGroupPkgs = mutableListOf<String>()
                var matchFound = false

                for (j in 0 until pkgsArray.length()) {
                    val pkg = pkgsArray.getString(j).trim()
                    currentGroupPkgs.add(pkg)
                    if (pkg == activePackage) matchFound = true
                }

                if (matchFound) {
                    matchedGroupName = groupObj.getString("name")
                    timeLimitMinutes = groupObj.getInt("timeLimitMinutes")
                    packagesInGroup.addAll(currentGroupPkgs)
                    break
                }
            }

            if (matchedGroupName == null) return

            val bonusKey = "flutter.bonus_seconds_$matchedGroupName"
            val bonusSeconds = prefs.getInt(bonusKey, 0)
            val bonusMinutes = bonusSeconds / 60
            val totalAllowedMinutes = timeLimitMinutes + bonusMinutes

            if (totalAllowedMinutes == 0) {
                Log.d(TAG, "Zero limit for $matchedGroupName — blocking immediately")
                blockAndKillApp(activePackage, matchedGroupName)
                return
            }

            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val calendar = Calendar.getInstance()
            calendar.set(Calendar.HOUR_OF_DAY, 0)
            calendar.set(Calendar.MINUTE, 0)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val startOfDay = calendar.timeInMillis
            val now = System.currentTimeMillis()

            var statsList = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, startOfDay, now)
            if (statsList.isNullOrEmpty()) {
                statsList = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startOfDay, now)
            }

            var totalUsageMs = 0L
            if (statsList != null) {
                for (stat in statsList) {
                    if (packagesInGroup.contains(stat.packageName)) {
                        totalUsageMs += stat.totalTimeInForeground
                    }
                }
            }

            val totalUsageMinutes = (totalUsageMs / 60000).toInt()
            Log.d(TAG, "Group: $matchedGroupName | Used: ${totalUsageMinutes}m | Limit: ${totalAllowedMinutes}m")

            if (totalUsageMinutes >= totalAllowedMinutes) {
                Log.d(TAG, "Limit reached. Blocking $activePackage")
                blockAndKillApp(activePackage, matchedGroupName)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error checking limits", e)
        }
    }

    private fun blockApp(groupName: String) {
        lastBlockTime = System.currentTimeMillis()

        try {
            performGlobalAction(GLOBAL_ACTION_BACK)
        } catch (_: Exception) {}

        val homeIntent = Intent(Intent.ACTION_MAIN)
        homeIntent.addCategory(Intent.CATEGORY_HOME)
        homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        homeIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        startActivity(homeIntent)

        val appIntent = Intent(this, MainActivity::class.java)
        appIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TASK
        appIntent.putExtra("SHOW_LOCK_SCREEN_APP_NAME", groupName)
        startActivity(appIntent)
    }

    private fun blockAndKillApp(packageToKill: String, groupName: String) {
        blockApp(groupName)
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.killBackgroundProcesses(packageToKill)
            Log.d(TAG, "Killed background processes for $packageToKill")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to kill $packageToKill", e)
        }
        try {
            performGlobalAction(GLOBAL_ACTION_BACK)
        } catch (_: Exception) {}
    }

    // ── Visible Packages Enforcement ──────────────────────────────────────

    private fun enforceVisiblePackages() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (groupsJsonStr == "[]") return

            val groupsArray = JSONArray(groupsJsonStr)
            val packageToGroup = mutableMapOf<String, Pair<String, Int>>()
            for (i in 0 until groupsArray.length()) {
                val groupObj = groupsArray.getJSONObject(i)
                val groupName = groupObj.getString("name")
                val limit = groupObj.getInt("timeLimitMinutes")
                val pkgs = groupObj.getJSONArray("packageNames")
                for (j in 0 until pkgs.length()) {
                    val pkg = pkgs.getString(j).trim()
                    packageToGroup[pkg] = Pair(groupName, limit)
                }
            }

            for (window in windows) {
                val root = window.root
                if (root != null) {
                    val pkg = root.packageName?.toString()?.trim() ?: continue
                    val pair = packageToGroup[pkg] ?: continue
                    val (groupName, limitMinutes) = pair

                    val totalUsageMinutes = getUsageMinutesForGroup(groupName, pkg)
                    val bonusKey = "flutter.bonus_seconds_" + groupName
                    val bonusSeconds = prefs.getInt(bonusKey, 0)
                    val totalAllowed = limitMinutes + (bonusSeconds / 60)
                    if (totalAllowed == 0 || totalUsageMinutes >= totalAllowed) {
                        Log.d(TAG, "Enforcing block for $pkg (group $groupName) via window check")
                        blockAndKillApp(pkg, groupName)
                        return
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in enforceVisiblePackages", e)
        }
    }

    private fun getUsageMinutesForGroup(groupName: String, samplePkg: String): Int {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val calendar = Calendar.getInstance()
            calendar.set(Calendar.HOUR_OF_DAY, 0)
            calendar.set(Calendar.MINUTE, 0)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val startOfDay = calendar.timeInMillis
            val now = System.currentTimeMillis()
            var stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, startOfDay, now)
            if (stats.isNullOrEmpty()) {
                stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startOfDay, now)
            }
            var totalMs = 0L
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            val groupsArray = JSONArray(groupsJsonStr)
            val pkgList = mutableListOf<String>()
            for (i in 0 until groupsArray.length()) {
                val g = groupsArray.getJSONObject(i)
                if (g.getString("name") == groupName) {
                    val pkgs = g.getJSONArray("packageNames")
                    for (j in 0 until pkgs.length()) {
                        pkgList.add(pkgs.getString(j).trim())
                    }
                }
            }
            for (stat in stats) {
                if (pkgList.contains(stat.packageName)) {
                    totalMs += stat.totalTimeInForeground
                }
            }
            (totalMs / 60000).toInt()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to compute usage for $groupName", e)
            0
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service Interrupted")
    }
}
