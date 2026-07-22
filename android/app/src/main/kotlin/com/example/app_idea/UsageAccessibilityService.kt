package com.example.app_idea

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.content.Context
import android.util.Log
import android.app.usage.UsageStatsManager
import android.app.ActivityManager
import org.json.JSONArray
import java.util.Calendar

class UsageAccessibilityService : AccessibilityService() {

    private val TAG = "UsageService"

    // Throttle: only re-check if the foreground package changed
    private var lastCheckedPackage: String = ""
    private var lastCheckTime: Long = 0L
    private var lastBlockTime: Long = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            val type = event?.eventType ?: return

            if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                type != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return

            val activePackage = event.packageName?.toString()?.trim() ?: return
            val className = event.className?.toString()?.trim()

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

            Log.d(TAG, "Checking package: $activePackage className: $className")
            checkAndEnforceLimits(activePackage, className)
            enforceVisiblePackages()
        } catch (e: Exception) {
            Log.e(TAG, "onAccessibilityEvent error", e)
        }
    }

    private fun checkAndEnforceLimits(activePackage: String, className: String?) {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"

            if (groupsJsonStr == "[]") return

            val groupsArray = JSONArray(groupsJsonStr)
            var matchedGroupName: String? = null
            var timeLimitMinutes = 0
            val packagesInGroup = mutableListOf<String>()
            var matchedBannedFeature: String? = null

            // Find if activePackage is in any group
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

                    // Check banned features with activity patterns
                    if (className != null && groupObj.has("bannedFeatures")) {
                        val bansArray = groupObj.getJSONArray("bannedFeatures")
                        for (b in 0 until bansArray.length()) {
                            val ban = bansArray.getJSONObject(b)
                            val featureName = ban.getString("name")
                            if (ban.has("activityPattern")) {
                                val pattern = ban.getString("activityPattern")
                                if (className.matches(Regex(pattern, RegexOption.IGNORE_CASE))) {
                                    matchedBannedFeature = featureName
                                    Log.d(TAG, "Banned feature detected: $featureName (className: $className matches $pattern)")
                                    break
                                }
                            }
                        }
                    }
                    break
                }
            }

            if (matchedGroupName == null) return // App is not tracked

            // If a banned feature with activity pattern was detected, block immediately
            if (matchedBannedFeature != null) {
                blockAndKillApp(activePackage, matchedGroupName, matchedBannedFeature)
                return
            }

            // Read bonus seconds, convert to whole minutes (floor — strict)
            val bonusKey = "flutter.bonus_seconds_$matchedGroupName"
            val bonusSeconds = prefs.getInt(bonusKey, 0)
            val bonusMinutes = bonusSeconds / 60
            val totalAllowedMinutes = timeLimitMinutes + bonusMinutes

            // --- Zero limit = ALWAYS BLOCK immediately, skip usage stats ---
            if (totalAllowedMinutes == 0) {
                Log.d(TAG, "Zero limit for $matchedGroupName — blocking immediately")
                blockAndKillApp(activePackage, matchedGroupName)
                return
            }

            // Get today's usage with INTERVAL_BEST for freshest data
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val calendar = Calendar.getInstance()
            calendar.set(Calendar.HOUR_OF_DAY, 0)
            calendar.set(Calendar.MINUTE, 0)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val startOfDay = calendar.timeInMillis
            val now = System.currentTimeMillis()

            // Use INTERVAL_BEST for most up-to-date data; fall back to INTERVAL_DAILY
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
            Log.d(TAG, "Group: $matchedGroupName | Used: ${totalUsageMinutes}m | Limit: ${totalAllowedMinutes}m | Raw ms: $totalUsageMs")

            if (totalUsageMinutes >= totalAllowedMinutes) {
                Log.d(TAG, "Limit reached. Blocking $activePackage")
                blockAndKillApp(activePackage, matchedGroupName)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error checking limits", e)
        }
    }

    private fun blockApp(groupName: String, bannedFeatureName: String? = null) {
        lastBlockTime = System.currentTimeMillis()

        // 0. Try to dismiss floating windows / bubbles with global back action
        try {
            performGlobalAction(GLOBAL_ACTION_BACK)
        } catch (_: Exception) {}

        // 1. Go to home screen
        val homeIntent = Intent(Intent.ACTION_MAIN)
        homeIntent.addCategory(Intent.CATEGORY_HOME)
        homeIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        homeIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        startActivity(homeIntent)

        // 2. Launch our app to show the lock screen over everything
        val appIntent = Intent(this, MainActivity::class.java)
        appIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TASK
        appIntent.putExtra("SHOW_LOCK_SCREEN_APP_NAME", groupName)
        if (bannedFeatureName != null) {
            appIntent.putExtra("SHOW_LOCK_SCREEN_FEATURE_NAME", bannedFeatureName)
        }
        startActivity(appIntent)
    }

    /**
     * Blocks the offending app and optionally kills its process.
     * This works for both foreground checks and split‑screen / PiP windows.
     */
    private fun blockAndKillApp(packageToKill: String, groupName: String, bannedFeatureName: String? = null) {
        // First, show the lock UI for the group.
        blockApp(groupName, bannedFeatureName)
        // Then attempt to kill the offending package.
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            am.killBackgroundProcesses(packageToKill)
            Log.d(TAG, "Killed background processes for $packageToKill")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to kill $packageToKill", e)
        }
        // Extra attempt for floating windows — send another back press
        try {
            performGlobalAction(GLOBAL_ACTION_BACK)
        } catch (_: Exception) {}
    }

    // ---------------------------------------------------------------------
    // Additional helpers for split‑screen / PiP enforcement
    // ---------------------------------------------------------------------

    /**
     * Checks every window currently owned by the AccessibilityService and blocks any
     * package that belongs to a group whose limit has been exceeded. This catches apps
     * that are visible in split‑screen or Picture‑in‑Picture mode where the normal
     * foreground‑package detection does not fire.
     */
    private fun enforceVisiblePackages() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val groupsJsonStr = prefs.getString("flutter.app_groups", "[]") ?: "[]"
            if (groupsJsonStr == "[]") return

            val groupsArray = JSONArray(groupsJsonStr)
            // Map each package to its group limit for quick lookup
            val packageToGroup = mutableMapOf<String, Pair<String, Int>>() // pkg -> (groupName, limitMinutes)
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

            // Iterate over all active windows and enforce limits
            for (window in windows) {
                val root = window.root
                if (root != null) {
                    val pkg = root.packageName?.toString()?.trim() ?: continue
                    val pair = packageToGroup[pkg] ?: continue
                    val (groupName, limitMinutes) = pair

                    // Calculate usage for this group (same logic as before)
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

    /**
     * Helper that returns the total usage minutes for the given group across the day.
     * Duplicated from checkAndEnforceLimits to keep the logic self‑contained.
     */
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

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        info.notificationTimeout = 100
        serviceInfo = info
        Log.d(TAG, "Service connected with flags: ${info.flags}")
    }

    override fun onInterrupt() {
        Log.d(TAG, "Service Interrupted")
    }
}
