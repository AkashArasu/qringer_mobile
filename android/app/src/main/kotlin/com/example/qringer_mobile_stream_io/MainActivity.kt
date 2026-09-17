package com.example.qringer_mobile_stream_io

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "qronly/pending_answer"
    private val prefs by lazy { getSharedPreferences("qronly_pending_answer", MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        captureAnswer(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        captureAnswer(intent)
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun captureAnswer(intent: Intent?) {
        if (intent?.action != CallkitConstants.ACTION_CALL_ACCEPT) return
        val data = intent.getBundleExtra("EXTRA_CALLKIT_CALL_DATA") ?: return
        val id = data.getString(CallkitConstants.EXTRA_CALLKIT_ID) ?: return
        val extra = data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA) as? Map<*, *> ?: return
        val cid = extra["callCid"] as? String ?: return
        val pending = JSONObject().put("id", id).put("callCid", cid)
            .put("savedAt", System.currentTimeMillis())
        // Persist before Flutter starts; clearing the ringing notification
        // cannot erase this Answer intent before Dart has handled it.
        prefs.edit().putString("answer", pending.toString()).commit()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> {
                        val raw = prefs.getString("answer", null)
                        val value = raw?.let { JSONObject(it) }
                        if (value == null || System.currentTimeMillis() - value.getLong("savedAt") > 120000) {
                            prefs.edit().remove("answer").apply()
                            result.success(null)
                        } else {
                            result.success(mapOf("id" to value.getString("id"), "isAccepted" to true,
                                "extra" to mapOf("callCid" to value.getString("callCid"))))
                        }
                    }
                    "ack" -> {
                        val raw = prefs.getString("answer", null)
                        if (raw != null && JSONObject(raw).getString("id") == call.arguments) {
                            prefs.edit().remove("answer").commit()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
