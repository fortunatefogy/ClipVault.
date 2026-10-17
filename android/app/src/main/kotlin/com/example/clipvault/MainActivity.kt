package com.example.clipvault

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.example.clipvault/share"
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shareChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedText" -> {
                        val sharedText = pendingSharedText ?: sharedTextFrom(intent)
                        pendingSharedText = null
                        result.success(sharedText)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val sharedText = sharedTextFrom(intent) ?: return
        pendingSharedText = sharedText
        shareChannel?.invokeMethod("sharedText", sharedText, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingSharedText = null
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
                Unit

            override fun notImplemented() = Unit
        })
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.dataString
            ?: intent.clipData?.getItemAt(0)?.coerceToText(this)?.toString()
    }
}
