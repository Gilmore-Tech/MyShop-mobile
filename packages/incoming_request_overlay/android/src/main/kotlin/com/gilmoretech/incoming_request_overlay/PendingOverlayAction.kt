package com.gilmoretech.incoming_request_overlay

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class PendingOverlayAction(
    val actionId: String,
    val action: String,
    val offerId: String,
    val offerType: String,
    val occurredAtMillis: Long,
    val payload: Map<String, String>,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "actionId" to actionId,
        "action" to action,
        "offerId" to offerId,
        "offerType" to offerType,
        "occurredAtMillis" to occurredAtMillis,
        "payload" to payload,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("actionId", actionId)
        put("action", action)
        put("offerId", offerId)
        put("offerType", offerType)
        put("occurredAtMillis", occurredAtMillis)
        put("payload", JSONObject(payload))
    }

    companion object {
        fun fromJson(json: JSONObject): PendingOverlayAction? {
            val actionId = json.optString("actionId").trim()
            val action = json.optString("action").trim()
            val offerId = json.optString("offerId").trim()
            val offerType = json.optString("offerType").trim()
            val occurredAtMillis = json.optLong("occurredAtMillis")
            if (actionId.isEmpty() || action.isEmpty() || offerId.isEmpty() ||
                offerType !in setOf("ride", "job") || occurredAtMillis <= 0L
            ) {
                return null
            }
            val payloadJson = json.optJSONObject("payload")
            val payload = buildMap {
                payloadJson?.keys()?.forEach { key ->
                    if (!payloadJson.isNull(key)) put(key, payloadJson.get(key).toString())
                }
            }
            return PendingOverlayAction(
                actionId = actionId,
                action = action,
                offerId = offerId,
                offerType = offerType,
                occurredAtMillis = occurredAtMillis,
                payload = payload,
            )
        }
    }
}

internal object PendingActionStore {
    private const val PREFERENCES = "incoming_request_overlay.pending_actions"
    private const val KEY_ACTIONS = "actions"
    private const val MAX_ACTIONS = 20
    private const val MAX_AGE_MILLIS = 24 * 60 * 60 * 1000L
    private val lock = Any()

    fun persist(context: Context, action: PendingOverlayAction): Boolean = synchronized(lock) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val existing = parse(prefs.getString(KEY_ACTIONS, null))
            .filter { now - it.occurredAtMillis <= MAX_AGE_MILLIS }
            .toMutableList()
        existing += action
        val bounded = existing.takeLast(MAX_ACTIONS)
        val array = JSONArray().apply { bounded.forEach { put(it.toJson()) } }
        prefs.edit().putString(KEY_ACTIONS, array.toString()).commit()
    }

    fun peek(context: Context): List<PendingOverlayAction> = synchronized(lock) {
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val actions = parse(prefs.getString(KEY_ACTIONS, null))
            .filter { now - it.occurredAtMillis <= MAX_AGE_MILLIS }
        val array = JSONArray().apply { actions.forEach { put(it.toJson()) } }
        prefs.edit().putString(KEY_ACTIONS, array.toString()).commit()
        actions
    }

    fun acknowledge(context: Context, actionId: String): Boolean = synchronized(lock) {
        if (actionId.isBlank()) return@synchronized false
        val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val remaining = parse(prefs.getString(KEY_ACTIONS, null))
            .filterNot { it.actionId == actionId }
        val array = JSONArray().apply { remaining.forEach { put(it.toJson()) } }
        prefs.edit().putString(KEY_ACTIONS, array.toString()).commit()
    }

    private fun parse(raw: String?): List<PendingOverlayAction> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    array.optJSONObject(index)?.let(PendingOverlayAction::fromJson)?.let(::add)
                }
            }
        }.getOrDefault(emptyList())
    }
}
