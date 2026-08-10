package com.gilmoretech.incoming_request_overlay

import android.content.Intent
import org.json.JSONObject

internal object OfferPayloadCodec {
    private const val EXTRA_PREFIX = "incoming_request_overlay."
    const val EXTRA_OFFER_ID = "${EXTRA_PREFIX}offer_id"
    const val EXTRA_OFFER_TYPE = "${EXTRA_PREFIX}offer_type"
    const val EXTRA_EXPIRES_AT = "${EXTRA_PREFIX}expires_at"
    const val EXTRA_TITLE = "${EXTRA_PREFIX}title"
    const val EXTRA_CUSTOMER_NAME = "${EXTRA_PREFIX}customer_name"
    const val EXTRA_AMOUNT = "${EXTRA_PREFIX}amount"
    const val EXTRA_AMOUNT_LABEL = "${EXTRA_PREFIX}amount_label"
    const val EXTRA_PRICING_SUMMARY = "${EXTRA_PREFIX}pricing_summary"
    const val EXTRA_DISTANCE = "${EXTRA_PREFIX}distance"
    const val EXTRA_DURATION = "${EXTRA_PREFIX}duration"
    const val EXTRA_PICKUP = "${EXTRA_PREFIX}pickup"
    const val EXTRA_DESTINATION = "${EXTRA_PREFIX}destination"
    const val EXTRA_CATEGORY = "${EXTRA_PREFIX}category"
    const val EXTRA_LOCATION = "${EXTRA_PREFIX}location"
    const val EXTRA_DESCRIPTION = "${EXTRA_PREFIX}description"
    const val EXTRA_PHOTO_URL = "${EXTRA_PREFIX}photo_url"
    const val EXTRA_MAP_PREVIEW_URL = "${EXTRA_PREFIX}map_preview_url"
    const val EXTRA_PAYLOAD_JSON = "${EXTRA_PREFIX}payload_json"

    fun put(intent: Intent, offer: OfferPayload): Intent = intent.apply {
        putExtra(EXTRA_OFFER_ID, offer.offerId)
        putExtra(EXTRA_OFFER_TYPE, offer.offerType)
        putExtra(EXTRA_EXPIRES_AT, offer.expiresAtMillis)
        putExtra(EXTRA_TITLE, offer.title)
        offer.customerName?.let { putExtra(EXTRA_CUSTOMER_NAME, it) }
        offer.amount?.let { putExtra(EXTRA_AMOUNT, it) }
        offer.amountLabel?.let { putExtra(EXTRA_AMOUNT_LABEL, it) }
        offer.pricingSummary?.let { putExtra(EXTRA_PRICING_SUMMARY, it) }
        offer.distance?.let { putExtra(EXTRA_DISTANCE, it) }
        offer.duration?.let { putExtra(EXTRA_DURATION, it) }
        offer.pickup?.let { putExtra(EXTRA_PICKUP, it) }
        offer.destination?.let { putExtra(EXTRA_DESTINATION, it) }
        offer.category?.let { putExtra(EXTRA_CATEGORY, it) }
        offer.location?.let { putExtra(EXTRA_LOCATION, it) }
        offer.description?.let { putExtra(EXTRA_DESCRIPTION, it) }
        offer.photoUrl?.let { putExtra(EXTRA_PHOTO_URL, it) }
        offer.mapPreviewUrl?.let { putExtra(EXTRA_MAP_PREVIEW_URL, it) }
        putExtra(EXTRA_PAYLOAD_JSON, JSONObject(offer.payload).toString())
    }

    fun read(intent: Intent): OfferPayload? {
        val offerId = intent.getStringExtra(EXTRA_OFFER_ID)?.trim().orEmpty()
        val offerType = intent.getStringExtra(EXTRA_OFFER_TYPE)?.trim().orEmpty()
        val title = intent.getStringExtra(EXTRA_TITLE)?.trim().orEmpty()
        val expiresAt = intent.getLongExtra(EXTRA_EXPIRES_AT, 0L)
        if (offerId.isEmpty() || offerType !in setOf("ride", "job") ||
            title.isEmpty() || expiresAt <= 0L
        ) {
            return null
        }
        return OfferPayload(
            offerId = offerId,
            offerType = offerType,
            expiresAtMillis = expiresAt,
            title = title,
            customerName = intent.cleanString(EXTRA_CUSTOMER_NAME),
            amount = intent.cleanString(EXTRA_AMOUNT),
            amountLabel = intent.cleanString(EXTRA_AMOUNT_LABEL),
            pricingSummary = intent.cleanString(EXTRA_PRICING_SUMMARY),
            distance = intent.cleanString(EXTRA_DISTANCE),
            duration = intent.cleanString(EXTRA_DURATION),
            pickup = intent.cleanString(EXTRA_PICKUP),
            destination = intent.cleanString(EXTRA_DESTINATION),
            category = intent.cleanString(EXTRA_CATEGORY),
            location = intent.cleanString(EXTRA_LOCATION),
            description = intent.cleanString(EXTRA_DESCRIPTION),
            photoUrl = intent.cleanString(EXTRA_PHOTO_URL),
            mapPreviewUrl = intent.cleanString(EXTRA_MAP_PREVIEW_URL),
            payload = parsePayload(intent.getStringExtra(EXTRA_PAYLOAD_JSON)),
        )
    }

    fun parsePayload(raw: String?): Map<String, String> {
        if (raw.isNullOrBlank()) return emptyMap()
        return runCatching {
            val json = JSONObject(raw)
            buildMap {
                json.keys().forEach { key ->
                    if (!json.isNull(key)) put(key, json.get(key).toString())
                }
            }
        }.getOrDefault(emptyMap())
    }

    private fun Intent.cleanString(key: String): String? =
        getStringExtra(key)?.trim()?.takeIf { it.isNotEmpty() }
}
