package com.assimilis.phone_data

import android.Manifest
import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Process
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.TimeZone

/**
 * Phone data for HES and the agents: the next alarm, screen time, the phone's calendars (including Google
 * calendars synced to the phone), and the last known location. Health data comes from Health Connect (health plugin).
 * Works from the background isolate too (WorkManager), so it only needs a Context.
 */
object PhoneDataChannel {
    const val NAME = "com.assimilis/phone_data"

    fun register(messenger: BinaryMessenger, context: Context) {
        val ctx = context.applicationContext
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "nextAlarm" -> {
                        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val next = am.nextAlarmClock
                        result.success(if (next == null) null else mapOf(
                            "at" to next.triggerTime,
                            "package" to (next.showIntent?.creatorPackage ?: "")
                        ))
                    }
                    "usageGranted" -> result.success(usageGranted(ctx))
                    "openUsageAccess" -> {
                        ctx.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    }
                    "usageToday" -> result.success(usageToday(ctx, call.argument<Number>("since")?.toLong()))
                    "calendars" -> result.success(calendars(ctx))
                    "events" -> result.success(events(
                        ctx,
                        call.argument<Number>("start")!!.toLong(),
                        call.argument<Number>("end")!!.toLong()
                    ))
                    "addEvent" -> result.success(addEvent(ctx, call.arguments as Map<*, *>))
                    "deleteEvent" -> {
                        val id = call.argument<Number>("id")!!.toLong()
                        val n = ctx.contentResolver.delete(
                            ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id), null, null
                        )
                        result.success(n > 0)
                    }
                    "lastLocation" -> result.success(lastLocation(ctx))
                    else -> result.notImplemented()
                }
            } catch (e: SecurityException) {
                result.error("PERMISSION", e.message, null)
            } catch (e: Exception) {
                result.error("ERROR", e.message, null)
            }
        }
    }

    private fun granted(ctx: Context, p: String) =
        ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun usageGranted(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29)
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        else @Suppress("DEPRECATION") ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Foreground minutes per app since [since] (default: midnight). */
    private fun usageToday(ctx: Context, since: Long?): Map<String, Any> {
        if (!usageGranted(ctx)) return mapOf("granted" to false)
        val start = since ?: Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = usm.queryAndAggregateUsageStats(start, System.currentTimeMillis())
        val pm = ctx.packageManager
        val apps = stats.values
            .filter { it.totalTimeInForeground > 60_000 && it.packageName != ctx.packageName }
            .sortedByDescending { it.totalTimeInForeground }
            .take(15)
            .map {
                val label = try {
                    pm.getApplicationLabel(pm.getApplicationInfo(it.packageName, 0)).toString()
                } catch (_: Exception) { it.packageName }
                mapOf("package" to it.packageName, "app" to label, "minutes" to (it.totalTimeInForeground / 60_000))
            }
        val total = stats.values.filter { it.packageName != ctx.packageName }.sumOf { it.totalTimeInForeground } / 60_000
        return mapOf("granted" to true, "total_minutes" to total, "apps" to apps)
    }

    private fun calendars(ctx: Context): List<Map<String, Any?>> {
        if (!granted(ctx, Manifest.permission.READ_CALENDAR)) throw SecurityException("Calendar permission not granted")
        val out = mutableListOf<Map<String, Any?>>()
        ctx.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(
                CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
                CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.ACCOUNT_TYPE,
                CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.IS_PRIMARY,
                CalendarContract.Calendars.VISIBLE
            ), null, null, null
        )?.use { c ->
            while (c.moveToNext()) {
                val access = c.getInt(4)
                out.add(mapOf(
                    "id" to c.getLong(0),
                    "name" to c.getString(1),
                    "account" to c.getString(2),
                    "google" to (c.getString(3) == "com.google"),
                    "writable" to (access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR),
                    "primary" to (c.getInt(5) == 1),
                    "visible" to (c.getInt(6) == 1)
                ))
            }
        }
        return out
    }

    private fun events(ctx: Context, start: Long, end: Long): List<Map<String, Any?>> {
        if (!granted(ctx, Manifest.permission.READ_CALENDAR)) throw SecurityException("Calendar permission not granted")
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, start); ContentUris.appendId(it, end)
        }.build()
        val out = mutableListOf<Map<String, Any?>>()
        ctx.contentResolver.query(
            uri,
            arrayOf(
                CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.CALENDAR_ID,
                CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY, CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.DESCRIPTION, CalendarContract.Instances.CALENDAR_DISPLAY_NAME
            ), null, null, CalendarContract.Instances.BEGIN + " ASC"
        )?.use { c ->
            while (c.moveToNext() && out.size < 200) {
                out.add(mapOf(
                    "id" to c.getLong(0), "calendar_id" to c.getLong(1), "title" to c.getString(2),
                    "start" to c.getLong(3), "end" to c.getLong(4), "all_day" to (c.getInt(5) == 1),
                    "location" to c.getString(6), "description" to (c.getString(7) ?: "").take(300),
                    "calendar" to c.getString(8)
                ))
            }
        }
        return out
    }

    private fun addEvent(ctx: Context, a: Map<*, *>): Long {
        if (!granted(ctx, Manifest.permission.WRITE_CALENDAR)) throw SecurityException("Calendar permission not granted")
        val calId = (a["calendar_id"] as? Number)?.toLong() ?: calendars(ctx)
            .filter { it["writable"] == true && it["visible"] == true }
            .let { list -> list.firstOrNull { it["primary"] == true && it["google"] == true } ?: list.firstOrNull { it["primary"] == true } ?: list.firstOrNull() }
            ?.get("id") as? Long ?: throw IllegalStateException("No writable calendar on this phone")
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calId)
            put(CalendarContract.Events.TITLE, a["title"] as String)
            put(CalendarContract.Events.DTSTART, (a["start"] as Number).toLong())
            put(CalendarContract.Events.DTEND, (a["end"] as Number).toLong())
            put(CalendarContract.Events.ALL_DAY, if (a["all_day"] == true) 1 else 0)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            (a["description"] as? String)?.let { put(CalendarContract.Events.DESCRIPTION, it) }
            (a["location"] as? String)?.let { put(CalendarContract.Events.EVENT_LOCATION, it) }
        }
        val uri = ctx.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: throw IllegalStateException("The calendar refused the event")
        val id = ContentUris.parseId(uri)
        (a["remind_minutes"] as? Number)?.let {
            ctx.contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, id)
                put(CalendarContract.Reminders.MINUTES, it.toInt())
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            })
        }
        return id
    }

    private fun lastLocation(ctx: Context): Map<String, Any>? {
        if (!granted(ctx, Manifest.permission.ACCESS_FINE_LOCATION) && !granted(ctx, Manifest.permission.ACCESS_COARSE_LOCATION)) {
            throw SecurityException("Location permission not granted")
        }
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val best = lm.getProviders(true)
            .mapNotNull { p -> try { lm.getLastKnownLocation(p) } catch (_: SecurityException) { null } }
            .maxByOrNull { it.time } ?: return null
        return mapOf("lat" to best.latitude, "lon" to best.longitude, "accuracy" to best.accuracy.toDouble(), "time" to best.time)
    }
}
