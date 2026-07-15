package com.gilmoretech.myshopprovider

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Only an actual voice call may cover the keyguard. Ride/job request
        // taps stay behind the device lock so Flutter cannot reveal names or
        // addresses before authentication.
        setCallLockScreenAccess(isIncomingCallIntent(intent))
    }

    override fun onNewIntent(intent: Intent) {
        setCallLockScreenAccess(isIncomingCallIntent(intent))
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.gilmoretech.myshopprovider/display",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                }
                "setCallLockScreenAccess" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        setCallLockScreenAccess(enabled)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isIncomingCallIntent(intent: Intent?): Boolean {
        val payload = intent?.getStringExtra("payload") ?: return false
        return runCatching {
            val type = JSONObject(payload).optString("type").replace('.', '_')
            type == "call_incoming"
        }.getOrDefault(false)
    }

    @Suppress("DEPRECATION")
    private fun setCallLockScreenAccess(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else if (enabled) {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        } else {
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }
}
