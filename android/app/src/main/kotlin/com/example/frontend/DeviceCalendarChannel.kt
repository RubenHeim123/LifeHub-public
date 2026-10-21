package com.example.frontend

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Zugriff auf den System-Kalender (CalendarContract): alle Konten, die am Handy im Kalender
 * erscheinen (Google, Samsung …). Lesen über Instances (Serien sind schon aufgelöst), Schreiben nur
 * in den eigenen lokalen Kalender „LifeHub“. Die Berechtigung fragt die Dart-Seite an.
 */
class DeviceCalendarChannel(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "lifehub/device_calendar")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    private val resolver: ContentResolver get() = context.contentResolver

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Abfragen nicht im UI-Thread
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "calendars" -> calendars()
                    "events" -> events(call)
                    "ensureCalendar" -> ensureCalendar(call.argument<String>("name")!!, call.argument<Int>("color")!!)
                    "upsertEvent" -> upsertEvent(call)
                    "deleteEvent" -> deleteEvent(call.argument<String>("eventId")!!)
                    "deleteCalendar" -> deleteCalendar(call.argument<String>("calendarId")!!)
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("permission", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("calendar", e.message, null) }
            }
        }
    }

    private fun calendars(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.VISIBLE,
        )
        resolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0).toString(),
                        "name" to (c.getString(1) ?: ""),
                        "account" to (c.getString(2) ?: ""),
                        "accountType" to (c.getString(3) ?: ""),
                        "color" to c.getInt(4),
                        "writable" to (c.getInt(5) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR),
                        "visible" to (c.getInt(6) == 1),
                    )
                )
            }
        }
        return out
    }

    private fun events(call: MethodCall): List<Map<String, Any?>> {
        val ids = call.argument<List<String>>("calendarIds") ?: emptyList()
        if (ids.isEmpty()) return emptyList()
        val from = call.argument<Number>("from")!!.toLong()
        val to = call.argument<Number>("to")!!.toLong()
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, from)
        ContentUris.appendId(builder, to)
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.DISPLAY_COLOR,
        )
        val selection = "${CalendarContract.Instances.CALENDAR_ID} IN (${ids.joinToString(",") { "?" }})"
        val out = mutableListOf<Map<String, Any?>>()
        resolver.query(builder.build(), projection, selection, ids.toTypedArray(), "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "eventId" to c.getLong(0).toString(),
                        "title" to (c.getString(1) ?: ""),
                        "begin" to c.getLong(2),
                        "end" to c.getLong(3),
                        "allDay" to (c.getInt(4) == 1),
                        "location" to c.getString(5),
                        "description" to c.getString(6),
                        "calendarId" to c.getLong(7).toString(),
                        "calendarName" to (c.getString(8) ?: ""),
                        "color" to c.getInt(9),
                    )
                )
            }
        }
        return out
    }

    private fun asSyncAdapter(uri: Uri, name: String): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, name)
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    /** Eigener lokaler Kalender (kein Google-Konto wird verändert). Liefert seine ID. */
    private fun ensureCalendar(name: String, color: Int): String {
        resolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.ACCOUNT_TYPE} = ? AND ${CalendarContract.Calendars.ACCOUNT_NAME} = ?",
            arrayOf(CalendarContract.ACCOUNT_TYPE_LOCAL, name),
            null,
        )?.use { c -> if (c.moveToFirst()) return c.getLong(0).toString() }
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, name)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, name)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, name)
            put(CalendarContract.Calendars.CALENDAR_COLOR, color)
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, name)
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            put(CalendarContract.Calendars.CALENDAR_TIME_ZONE, TimeZone.getDefault().id)
        }
        val uri = resolver.insert(asSyncAdapter(CalendarContract.Calendars.CONTENT_URI, name), values)
            ?: throw IllegalStateException("Kalender konnte nicht angelegt werden")
        return ContentUris.parseId(uri).toString()
    }

    /** Legt einen Termin an oder ändert ihn. Fehlt der alte Termin (z. B. anderes Gerät), wird neu angelegt. */
    private fun upsertEvent(call: MethodCall): String {
        val calendarId = call.argument<String>("calendarId")!!.toLong()
        val allDay = call.argument<Boolean>("allDay") ?: false
        val start = call.argument<Number>("start")!!.toLong()
        val end = call.argument<Number>("end")!!.toLong()
        val rrule = call.argument<String>("rrule")
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, call.argument<String>("title") ?: "")
            put(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
            put(CalendarContract.Events.DTSTART, start)
            put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
            // Ganztägig: UTC-Mitternacht, sonst die Zeitzone des Handys
            put(CalendarContract.Events.EVENT_TIMEZONE, if (allDay) "UTC" else TimeZone.getDefault().id)
            put(CalendarContract.Events.HAS_ALARM, 0)
            if (rrule != null) {
                // Serien brauchen DURATION statt DTEND
                put(CalendarContract.Events.RRULE, rrule)
                put(CalendarContract.Events.DURATION, if (allDay) "P${((end - start) / 86_400_000L).coerceAtLeast(1)}D" else "P${((end - start) / 1000L).coerceAtLeast(60)}S")
                putNull(CalendarContract.Events.DTEND)
            } else {
                put(CalendarContract.Events.DTEND, end)
                putNull(CalendarContract.Events.RRULE)
                putNull(CalendarContract.Events.DURATION)
            }
        }
        val existing = call.argument<String>("eventId")?.toLongOrNull()
        if (existing != null) {
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, existing)
            if (resolver.update(uri, values, "${CalendarContract.Events.CALENDAR_ID} = ?", arrayOf(calendarId.toString())) > 0) {
                return existing.toString()
            }
        }
        val uri = resolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: throw IllegalStateException("Termin konnte nicht angelegt werden")
        return ContentUris.parseId(uri).toString()
    }

    private fun deleteEvent(eventId: String): Boolean {
        val id = eventId.toLongOrNull() ?: return false
        return resolver.delete(ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id), null, null) > 0
    }

    private fun deleteCalendar(calendarId: String): Boolean {
        val id = calendarId.toLongOrNull() ?: return false
        val name = resolver.query(
            ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, id),
            arrayOf(CalendarContract.Calendars.ACCOUNT_NAME),
            null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: return false
        val uri = asSyncAdapter(ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, id), name)
        return resolver.delete(uri, null, null) > 0
    }
}
