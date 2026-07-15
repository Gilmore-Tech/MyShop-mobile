package com.gilmoretech.incoming_request_overlay

data class OfferPayload(
    val offerId: String,
    val offerType: String,
    val expiresAtMillis: Long,
    val title: String,
    val customerName: String?,
    val amount: String?,
    val distance: String?,
    val pickup: String?,
    val destination: String?,
    val category: String?,
    val location: String?,
    val description: String?,
    val photoUrl: String?,
    val payload: Map<String, String>,
) {
    val identity: String get() = "$offerType:$offerId"

    fun isExpired(nowMillis: Long = System.currentTimeMillis()): Boolean =
        expiresAtMillis <= nowMillis

    companion object {
        private val validTypes = setOf("ride", "job")

        fun fromMap(raw: Map<*, *>): OfferPayload? {
            val offerId = raw.string("offerId") ?: return null
            val offerType = raw.string("offerType") ?: return null
            if (offerType !in validTypes) return null
            val expiresAtMillis = raw.long("expiresAtMillis") ?: return null
            if (expiresAtMillis <= 0L) return null
            val title = raw.string("title") ?: return null
            val rawPayload = raw["payload"] as? Map<*, *>
            val payload = buildMap {
                rawPayload?.forEach { (key, value) ->
                    if (key != null && value != null) {
                        put(key.toString(), value.toString())
                    }
                }
            }
            return OfferPayload(
                offerId = offerId,
                offerType = offerType,
                expiresAtMillis = expiresAtMillis,
                title = title,
                customerName = raw.string("customerName"),
                amount = raw.string("amount"),
                distance = raw.string("distance"),
                pickup = raw.string("pickup"),
                destination = raw.string("destination"),
                category = raw.string("category"),
                location = raw.string("location"),
                description = raw.string("description"),
                photoUrl = raw.string("photoUrl"),
                payload = payload,
            )
        }

        private fun Map<*, *>.string(key: String): String? =
            this[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }

        private fun Map<*, *>.long(key: String): Long? = when (val value = this[key]) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
        }
    }
}
