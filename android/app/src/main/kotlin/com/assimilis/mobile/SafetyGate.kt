package com.assimilis.mobile

import android.accessibilityservice.AccessibilityService
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * On-device confirmation for risky phone-control actions.
 *
 * The check lives here, in the native AccessibilityService, so no model output, prompt or Dart code
 * can skip it. A risky action (send, pay, buy, delete, transfer, ... or anything inside a banking or
 * payment app) shows an Allow / Deny card drawn by the service itself (TYPE_ACCESSIBILITY_OVERLAY).
 * Nothing happens until the person taps Allow. Deny, or no answer within 60 s, refuses the action.
 */
object SafetyGate {

    private val riskyWords = listOf(
        "send", "pay", "payment", "buy", "purchase", "order", "checkout", "check out", "place order",
        "transfer", "withdraw", "deposit", "donate", "subscribe", "confirm", "approve", "authorize",
        "authorise", "delete", "remove", "erase", "wipe", "reset", "uninstall", "clear data",
        "post", "publish", "share", "tweet", "reply all", "forward", "call", "submit", "sign out",
        "log out", "factory", "format", "empty trash", "unsubscribe", "accept"
    )

    /** Package-name fragments of banking, payment, wallet and trading apps. */
    private val moneyPackages = listOf(
        "bank", "pay", "wallet", "money", "cash", "finance", "credit", "venmo", "zelle", "revolut",
        "wise", "monzo", "chime", "coinbase", "binance", "crypto", "kraken", "robinhood", "trading",
        "invest", "stripe", "western", "remit", "lynk", "scotia", "ncb", "jmmb", "sagicor"
    )

    private val main = Handler(Looper.getMainLooper())
    private var showing: View? = null

    private const val PREFS = "assimilis_safety"
    private const val KEY_FULL_ALLOW = "full_allow"

    /** Full allow mode: the owner turned prompts off, so every action runs without asking. */
    fun isFullAllow(context: android.content.Context): Boolean =
        context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).getBoolean(KEY_FULL_ALLOW, false)

    fun setFullAllow(context: android.content.Context, on: Boolean) {
        context.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE).edit().putBoolean(KEY_FULL_ALLOW, on).apply()
    }

    fun riskyReason(label: String?, packageName: String?): String? {
        val pkg = packageName?.lowercase().orEmpty()
        if (pkg.isNotEmpty() && pkg != "com.assimilis.mobile" && moneyPackages.any { pkg.contains(it) }) {
            return "This is a banking or payment app ($pkg)."
        }
        val text = label?.lowercase()?.trim().orEmpty()
        if (text.isEmpty()) return null
        val hit = riskyWords.firstOrNull { w -> Regex("(^|[^a-z])" + Regex.escape(w) + "([^a-z]|$)").containsMatchIn(text) }
        return hit?.let { "The button or field says \"${label!!.take(60)}\"." }
    }

    /**
     * Run [action] only after the person allows it. [onDenied] runs if they deny or don't answer.
     * Must be called on the main thread.
     */
    fun confirm(
        service: AccessibilityService,
        what: String,
        why: String,
        action: () -> Unit,
        onDenied: () -> Unit
    ) {
        if (isFullAllow(service)) { action(); return }
        dismiss(service)
        val wm = service.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager
        var answered = false

        fun dp(v: Int) = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), service.resources.displayMetrics
        ).toInt()

        val card = LinearLayout(service).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(18), dp(20), dp(14))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#171b26"))
                cornerRadius = dp(18).toFloat()
                setStroke(dp(2), Color.parseColor("#3d8c6e"))
            }
        }
        card.addView(TextView(service).apply {
            text = "Assimilis wants to: $what"
            setTextColor(Color.WHITE)
            textSize = 17f
        })
        card.addView(TextView(service).apply {
            text = "$why\nAllow only if you asked for this."
            setTextColor(Color.parseColor("#b8c4d6"))
            textSize = 14f
            setPadding(0, dp(8), 0, dp(12))
        })
        val row = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val deny = Button(service).apply {
            text = "Deny"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#3a2230"))
        }
        val allow = Button(service).apply {
            text = "Allow"
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#3d8c6e"))
        }
        row.addView(deny)
        row.addView(View(service), LinearLayout.LayoutParams(dp(12), 1))
        row.addView(allow)
        card.addView(row)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM
            x = 0
            y = dp(48)
            horizontalMargin = 0.04f
        }

        val timeout = Runnable {
            if (!answered) { answered = true; dismiss(service); onDenied() }
        }
        allow.setOnClickListener {
            if (answered) return@setOnClickListener
            answered = true
            main.removeCallbacks(timeout)
            dismiss(service)
            // Let the overlay leave the screen before the gesture lands underneath it.
            main.postDelayed({ action() }, 250)
        }
        deny.setOnClickListener {
            if (answered) return@setOnClickListener
            answered = true
            main.removeCallbacks(timeout)
            dismiss(service)
            onDenied()
        }

        try {
            wm.addView(card, params)
            showing = card
            main.postDelayed(timeout, 60_000)
        } catch (e: Exception) {
            // If the card can't be shown, refuse rather than act unconfirmed.
            answered = true
            onDenied()
        }
    }

    private fun dismiss(service: AccessibilityService) {
        val v = showing ?: return
        showing = null
        try {
            (service.getSystemService(android.content.Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (_: Exception) {
        }
    }
}
