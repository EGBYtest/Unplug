package com.example.app_idea

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.os.Bundle

class MainActivity : FlutterActivity() {

    private val CHANNEL = "app_closure"
    private var methodChannel: MethodChannel? = null
    private var pendingLockScreenApp: String? = null
    private var pendingLockScreenFeature: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "forceCloseApp" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    val handler = AppClosureHandler(applicationContext)
                    val success = handler.forceCloseApp(packageName)
                    result.success(success)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                "hasUsageAccess" -> {
                    val appOps = getSystemService(APP_OPS_SERVICE) as android.app.AppOpsManager
                    val mode = appOps.checkOpNoThrow(
                        android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                        android.os.Process.myUid(),
                        packageName
                    )
                    result.success(mode == android.app.AppOpsManager.MODE_ALLOWED)
                }
                "hasAccessibilityEnabled" -> {
                    val ourService = "$packageName/${packageName}.UsageAccessibilityService"
                    val enabledServices = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                    ) ?: ""
                    result.success(enabledServices.split(":").contains(ourService))
                }
                "getInstalledApps" -> {
                    val pm = packageManager
                    val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    val appList = mutableListOf<Map<String, String>>()
                    for (appInfo in packages) {
                        val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                                          (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                        val name = pm.getApplicationLabel(appInfo).toString()
                        val pkgName = appInfo.packageName
                        // Skip packages with no launcher intent (pure background services)
                        val launchIntent = pm.getLaunchIntentForPackage(pkgName)
                        if (launchIntent != null) {
                            appList.add(mapOf(
                                "name" to name,
                                "packageName" to pkgName,
                                "isSystem" to if (isSystemApp) "true" else "false"
                            ))
                        }
                    }
                    android.util.Log.d("AppPicker", "Found ${packages.size} total packages, filtered down to ${appList.size} apps.")
                    result.success(appList)
                }
                else -> result.notImplemented()
            }
        }

        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        val appName = pendingLockScreenApp ?: return
        val feature = pendingLockScreenFeature
        pendingLockScreenApp = null
        pendingLockScreenFeature = null
        sendLockScreenCall(appName, feature ?: "")
    }

    private fun sendLockScreenCall(appName: String, bannedFeature: String) {
        val handler = Handler(Looper.getMainLooper())
        var attempts = 0
        val maxAttempts = 10 // 10 × 300ms = 3s
        val args = mapOf("appName" to appName, "bannedFeature" to bannedFeature)

        fun tryInvoke() {
            attempts++
            val engine = flutterEngine
            if (engine != null && engine.dartExecutor.isExecutingDart && methodChannel != null) {
                methodChannel!!.invokeMethod("showLockScreen", args)
            } else if (attempts < maxAttempts) {
                handler.postDelayed({ tryInvoke() }, 300)
            } else {
                android.util.Log.e("MainActivity", "Failed to invoke showLockScreen: Flutter not ready after ${maxAttempts * 300}ms")
            }
        }
        handler.postDelayed({ tryInvoke() }, 200)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val appName = intent.getStringExtra("SHOW_LOCK_SCREEN_APP_NAME")
        val featureName = intent.getStringExtra("SHOW_LOCK_SCREEN_FEATURE_NAME")
        if (appName != null) {
            pendingLockScreenApp = appName
            pendingLockScreenFeature = featureName
            intent.removeExtra("SHOW_LOCK_SCREEN_APP_NAME")
            intent.removeExtra("SHOW_LOCK_SCREEN_FEATURE_NAME")
        }
    }
}
