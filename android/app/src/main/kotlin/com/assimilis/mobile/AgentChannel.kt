package com.assimilis.mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Phone Agent bridge (channel names kept from PrivateAgent so its Dart code works unchanged).
 * Every action that can change something (tap, type, Enter) goes through [SafetyGate] first.
 */
object AgentChannel {
    const val METHODS = "com.privateagent/accessibility"
    const val EVENTS = "com.privateagent/accessibility_events"

    fun registerEvents(engine: FlutterEngine, activity: android.app.Activity) {
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    AgentAccessibilityService.eventListener = { m ->
                        activity.runOnUiThread { events?.success(m) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    AgentAccessibilityService.eventListener = null
                }
            }
        )
    }

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler { call, result ->
            val service = AgentAccessibilityService.instance
            fun needService(block: (AgentAccessibilityService) -> Unit) {
                if (service == null) result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                else block(service)
            }
            fun gated(s: AgentAccessibilityService, what: String, why: String?, act: () -> Boolean) {
                if (why == null) { result.success(act()); return }
                SafetyGate.confirm(
                    s, what, why,
                    action = { result.success(act()) },
                    onDenied = { result.error("USER_DENIED", "The person denied: $what", null) }
                )
            }

            when (call.method) {
                "ping" -> result.success(true)
                "getFullAllow" -> result.success(SafetyGate.isFullAllow(context))
                "setFullAllow" -> {
                    SafetyGate.setFullAllow(context, call.argument<Boolean>("on") == true)
                    result.success(true)
                }
                "logToNative" -> {
                    android.util.Log.d("AssimilisAgent", call.argument<String>("message") ?: "")
                    result.success(true)
                }
                "isServiceRunning" -> result.success(AgentAccessibilityService.isRunning())
                "checkOverlayPermission" -> result.success(Settings.canDrawOverlays(context))
                "requestOverlayPermission" -> {
                    context.startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(true)
                }
                "showMacroOverlay" -> result.error("NOT_SUPPORTED", "Macro overlay not supported", null)
                "hideMacroOverlay" -> result.success(true)
                "openAccessibilitySettings" -> {
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "confirm" -> if (SafetyGate.isFullAllow(context)) result.success(true) else needService { s ->
                    SafetyGate.confirm(
                        s,
                        call.argument<String>("what") ?: "do something",
                        call.argument<String>("why") ?: "This action can't easily be undone.",
                        action = { result.success(true) },
                        onDenied = { result.error("USER_DENIED", "The person denied it", null) }
                    )
                }
                "dumpScreen" -> needService { result.success(it.dumpScreen()) }
                "takeScreenshot" -> needService { s ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        s.takeScreenshot { b64 ->
                            if (b64 != null) result.success(b64)
                            else result.error("SCREENSHOT_FAILED", "Failed to capture screenshot", null)
                        }
                    } else result.error("UNSUPPORTED_VERSION", "Screenshot requires Android 11+", null)
                }
                "clickByText" -> needService { s ->
                    val text = call.argument<String>("text") ?: ""
                    gated(s, "tap \"${text.take(60)}\"", SafetyGate.riskyReason(text, s.getCurrentPackage())) {
                        s.clickByText(text)
                    }
                }
                "clickAt" -> needService { s ->
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    val label = s.labelAt(x, y)
                    val what = if (label.isBlank()) "tap the screen at (${x.toInt()}, ${y.toInt()})" else "tap \"${label.take(60)}\""
                    gated(s, what, SafetyGate.riskyReason(label, s.getCurrentPackage())) {
                        s.clickAtCoordinates(x, y)
                    }
                }
                "typeText" -> needService { s ->
                    val text = call.argument<String>("text") ?: ""
                    val hint = call.argument<String>("fieldHint")
                    if (s.targetIsPassword(hint) && !SafetyGate.isFullAllow(context)) {
                        result.error("PASSWORD_FIELD", "Assimilis never types into password fields. Ask the person to type it.", null)
                    } else {
                        gated(s, "type \"${text.take(60)}\"", SafetyGate.riskyReason(null, s.getCurrentPackage())) {
                            s.typeText(text, hint)
                        }
                    }
                }
                "pressEnter" -> needService { s ->
                    gated(s, "press Enter", s.enterRisk() ?: SafetyGate.riskyReason(null, s.getCurrentPackage())) {
                        s.pressEnter()
                    }
                }
                "scroll" -> needService {
                    result.success(it.scroll(call.argument<String>("direction") ?: "down", call.argument<String>("target")))
                }
                "swipe" -> needService {
                    result.success(
                        it.swipe(
                            call.argument<Double>("startX")?.toFloat() ?: 0f,
                            call.argument<Double>("startY")?.toFloat() ?: 0f,
                            call.argument<Double>("endX")?.toFloat() ?: 0f,
                            call.argument<Double>("endY")?.toFloat() ?: 0f
                        )
                    )
                }
                "showToast" -> {
                    android.widget.Toast.makeText(context, call.argument<String>("message") ?: "", android.widget.Toast.LENGTH_SHORT).show()
                    result.success(true)
                }
                "pressBack" -> needService { result.success(it.pressBack()) }
                "pressHome" -> needService { result.success(it.pressHome()) }
                "openNotifications" -> needService { result.success(it.openNotifications()) }
                "getCurrentPackage" -> needService { result.success(it.getCurrentPackage()) }
                else -> result.notImplemented()
            }
        }
    }
}

/** Lets the Phone Agent's floating overlay engine reach the accessibility channel. */
class BackgroundEngineReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val engine = io.flutter.embedding.engine.FlutterEngineCache.getInstance().get("myCachedEngine") ?: return
        AgentChannel.register(engine, context.applicationContext)
    }
}
