package com.example.app_idea

import android.content.Intent
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings
import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo

class MainActivity : FlutterActivity() {

    private val CHANNEL = "app_closure"
    private var channel: MethodChannel? = null
    private var pendingApp: String? = null
    private var pendingFeature: String? = null
    private var lockScreenActive = false

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "lockScreenDismissed" -> { lockScreenActive = false; result.success(true) }
                "forceCloseApp" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    result.success(AppClosureHandler(applicationContext).forceCloseApp(pkg))
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }); result.success(true)
                }
                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }); result.success(true)
                }
                "hasUsageAccess" -> {
                    val ops = getSystemService(APP_OPS_SERVICE) as android.app.AppOpsManager
                    result.success(ops.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName) == android.app.AppOpsManager.MODE_ALLOWED)
                }
                "hasAccessibilityEnabled" -> {
                    val our = "$packageName/$packageName.UsageAccessibilityService"
                    result.success((Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: "").split(":").contains(our))
                }
                "getDeviceManufacturer" -> {
                    result.success(android.os.Build.MANUFACTURER)
                }
                "getInstalledApps" -> {
                    val pm = packageManager
                    val list = pm.getInstalledApplications(PackageManager.GET_META_DATA).mapNotNull {
                        if (pm.getLaunchIntentForPackage(it.packageName) != null) {
                            val sys = (it.flags and ApplicationInfo.FLAG_SYSTEM) != 0 && (it.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                            mapOf("name" to pm.getApplicationLabel(it).toString(), "packageName" to it.packageName, "isSystem" to if (sys) "true" else "false")
                        } else null
                    }
                    result.success(list)
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        val app = pendingApp ?: return
        val feat = pendingFeature
        pendingApp = null; pendingFeature = null
        enterLockScreenMode(app, feat ?: "")
    }

    private fun enterLockScreenMode(app: String, feature: String) {
        lockScreenActive = true
        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)

        // retry method channel up to 3s
        var attempts = 0
        val h = android.os.Handler(android.os.Looper.getMainLooper())
        fun trySend() {
            attempts++
            val engine = flutterEngine
            if (engine != null && engine.dartExecutor.isExecutingDart && channel != null) {
                channel!!.invokeMethod("showLockScreen", mapOf("appName" to app, "bannedFeature" to feature))
            } else if (attempts < 10) {
                h.postDelayed({ trySend() }, 300)
            }
        }
        h.postDelayed({ trySend() }, 200)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && lockScreenActive) {
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        }
    }

    override fun onBackPressed() { if (lockScreenActive) return; super.onBackPressed() }
    override fun onKeyDown(key: Int, event: KeyEvent?): Boolean {
        if (lockScreenActive && key == KeyEvent.KEYCODE_BACK) return true
        return super.onKeyDown(key, event)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); handleIntent(intent) }

    private fun handleIntent(intent: Intent) {
        val app = intent.getStringExtra("SHOW_LOCK_SCREEN_APP_NAME") ?: return
        pendingApp = app
        pendingFeature = intent.getStringExtra("SHOW_LOCK_SCREEN_FEATURE_NAME")
        intent.removeExtra("SHOW_LOCK_SCREEN_APP_NAME")
        intent.removeExtra("SHOW_LOCK_SCREEN_FEATURE_NAME")
    }
}
