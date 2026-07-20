package com.gilmoretech.incoming_request_overlay

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.UUID

class IncomingRequestActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val actionName = intent.getStringExtra(EXTRA_ACTION)?.trim().orEmpty()
        val offerId = intent.getStringExtra(OfferPayloadCodec.EXTRA_OFFER_ID)?.trim().orEmpty()
        val offerType = intent.getStringExtra(OfferPayloadCodec.EXTRA_OFFER_TYPE)?.trim().orEmpty()
        if (!isValidAction(actionName, offerType) || offerId.isEmpty()) return

        val action = PendingOverlayAction(
            actionId = UUID.randomUUID().toString(),
            action = actionName,
            offerId = offerId,
            offerType = offerType,
            occurredAtMillis = System.currentTimeMillis(),
            payload = OfferPayloadCodec.parsePayload(
                intent.getStringExtra(OfferPayloadCodec.EXTRA_PAYLOAD_JSON),
            ),
        )

        // Durability comes first. Starting an Activity may be delayed or denied
        // by an OEM, while Flutter's event sink may not exist in a cold process.
        PendingActionStore.persist(context, action)
        OverlayActionEvents.emit(action)
        IncomingRequestOverlayService.requestDismiss(context, offerType, offerId)
        launchHostApplication(context, action)
    }

    private fun launchHostApplication(context: Context, action: PendingOverlayAction) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: return
        launchIntent.apply {
            this.action = ACTION_OPEN_HOST
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_ACTION, action.action)
            putExtra(OfferPayloadCodec.EXTRA_OFFER_ID, action.offerId)
            putExtra(OfferPayloadCodec.EXTRA_OFFER_TYPE, action.offerType)
            putExtra(OfferPayloadCodec.EXTRA_PAYLOAD_JSON, JSONObjectCompat.encode(action.payload))
        }
        runCatching { context.startActivity(launchIntent) }
    }

    companion object {
        const val EXTRA_ACTION = "incoming_request_overlay.action"
        const val ACTION_OPEN_HOST = "com.gilmoretech.incoming_request_overlay.OPEN_HOST"

        private val rideActions = setOf("ride_accept", "ride_skip", "ride_view")
        private val jobActions = setOf("job_bid", "job_skip", "job_view")

        fun pendingIntent(
            context: Context,
            offer: OfferPayload,
            action: String,
        ): PendingIntent {
            val intent = Intent(context, IncomingRequestActionReceiver::class.java).apply {
                putExtra(EXTRA_ACTION, action)
                putExtra(OfferPayloadCodec.EXTRA_OFFER_ID, offer.offerId)
                putExtra(OfferPayloadCodec.EXTRA_OFFER_TYPE, offer.offerType)
                putExtra(
                    OfferPayloadCodec.EXTRA_PAYLOAD_JSON,
                    JSONObjectCompat.encode(offer.payload),
                )
            }
            val requestCode = "${offer.identity}:$action".hashCode() and Int.MAX_VALUE
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getBroadcast(context, requestCode, intent, flags)
        }

        private fun isValidAction(action: String, offerType: String): Boolean = when (offerType) {
            "ride" -> action in rideActions
            "job" -> action in jobActions
            else -> false
        }
    }
}

private object JSONObjectCompat {
    fun encode(values: Map<String, String>): String = org.json.JSONObject(values).toString()
}
