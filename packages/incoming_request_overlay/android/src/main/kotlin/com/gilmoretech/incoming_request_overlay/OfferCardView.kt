package com.gilmoretech.incoming_request_overlay

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.concurrent.Future
import kotlin.math.max

internal class OfferCardView(
    context: Context,
    private val offer: OfferPayload,
    private val isLocked: Boolean,
    private val onUnlockRequested: () -> Unit,
) : LinearLayout(context) {
    private val countdown = textView(sizeSp = 16f, bold = true, color = GOLD)
    private var thumbnailFuture: Future<*>? = null
    private var thumbnailView: ImageView? = null

    init {
        orientation = VERTICAL
        elevation = dp(14).toFloat()
        setPadding(dp(18), dp(16), dp(18), dp(16))
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(22).toFloat()
            setColor(NAVY)
            setStroke(dp(1), Color.argb(80, 255, 255, 255))
        }
        contentDescription = offer.title

        addView(header())
        addView(textView(sizeSp = 21f, bold = true).apply {
            text = offer.title
            setPadding(0, dp(10), 0, dp(8))
        })

        if (isLocked) {
            addView(textView(sizeSp = 14f, color = MUTED).apply {
                text = context.getString(R.string.incoming_request_overlay_locked)
                setPadding(0, 0, 0, dp(8))
            })
            addSafeLockedDetails()
        } else {
            addUnlockedJobThumbnail()
            addUnlockedDetails()
        }

        addView(actions(), LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(14)
        })
    }

    fun updateCountdown(nowMillis: Long = System.currentTimeMillis()) {
        val remainingMillis = max(0L, offer.expiresAtMillis - nowMillis)
        val seconds = (remainingMillis + 999L) / 1000L
        countdown.text = "${seconds}s"
        countdown.contentDescription = "$seconds seconds remaining"
    }

    override fun onDetachedFromWindow() {
        thumbnailFuture?.cancel(true)
        thumbnailFuture = null
        thumbnailView?.setImageDrawable(null)
        thumbnailView = null
        super.onDetachedFromWindow()
    }

    private fun header(): View = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(textView(sizeSp = 12f, bold = true, color = GOLD).apply {
            text = if (offer.offerType == "ride") "NEW RIDE REQUEST" else "NEW JOB REQUEST"
            letterSpacing = 0.08f
        }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        addView(countdown)
    }

    private fun addSafeLockedDetails() {
        if (offer.offerType == "job") addDetail("Category", offer.category)
        if (offer.offerType == "ride") {
            addDetail("Fare", offer.amount)
        } else {
            addJobPricing()
        }
        addDetail("Distance", offer.distance)
    }

    private fun addUnlockedDetails() {
        addDetail(if (offer.offerType == "ride") "Passenger" else "Client", offer.customerName)
        if (offer.offerType == "ride") {
            addDetail("Fare", offer.amount)
            addDetail("Distance", offer.distance)
            addDetail("Pickup", offer.pickup)
            addDetail("Destination", offer.destination)
        } else {
            addDetail("Category", offer.category)
            addJobPricing()
            addDetail("Distance", offer.distance)
            addDetail("Location", offer.location)
            addDetail("Request", offer.description, maxLines = 2)
        }
    }

    /**
     * The current job model has a category minimum bid, not a customer-entered
     * budget. Keep that distinction explicit so providers are never shown a
     * made-up budget value.
     */
    private fun addJobPricing() {
        val raw = offer.amount?.trim()?.takeIf { it.isNotEmpty() } ?: return
        if (raw.startsWith("Minimum ")) {
            addDetail("Minimum bid", raw.removePrefix("Minimum "))
        } else {
            addDetail("Quote", raw)
        }
    }

    private fun addUnlockedJobThumbnail() {
        val url = offer.photoUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return
        if (offer.offerType != "job") return
        val image = ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = "Job photo"
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(12).toFloat()
                setColor(Color.argb(45, 255, 255, 255))
            }
            clipToOutline = true
        }
        thumbnailView = image
        addView(image, LayoutParams(LayoutParams.MATCH_PARENT, dp(92)).apply {
            bottomMargin = dp(8)
        })
        thumbnailFuture = RemoteThumbnailLoader.load(url, dp(240)) { bitmap ->
            if (isAttachedToWindow && bitmap != null) image.setImageBitmap(bitmap)
        }
    }

    private fun addDetail(label: String, value: String?, maxLines: Int = 1) {
        if (value.isNullOrBlank()) return
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.TOP
            setPadding(0, dp(3), 0, dp(3))
            addView(textView(sizeSp = 13f, bold = true, color = MUTED).apply {
                text = label
            }, LayoutParams(dp(86), LayoutParams.WRAP_CONTENT))
            addView(textView(sizeSp = 14f).apply {
                text = value
                this.maxLines = maxLines
                ellipsize = android.text.TextUtils.TruncateAt.END
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        })
    }

    private fun actions(): View {
        if (isLocked) {
            return actionButton(
                context.getString(R.string.incoming_request_overlay_unlock_action),
                primary = true,
                onPressed = onUnlockRequested,
            )
        }
        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER
            val actions = if (offer.offerType == "ride") {
                listOf(
                    Triple("SKIP", "ride_skip", false),
                    Triple("VIEW", "ride_view", false),
                    Triple("ACCEPT", "ride_accept", true),
                )
            } else {
                listOf(
                    Triple("SKIP", "job_skip", false),
                    Triple("VIEW", "job_view", false),
                    Triple("SUBMIT BID", "job_bid", true),
                )
            }
            actions.forEachIndexed { index, (label, action, primary) ->
                if (index > 0) addView(View(context), LayoutParams(dp(7), 1))
                addView(
                    actionButton(label, primary) {
                        val pendingIntent = IncomingRequestActionReceiver.pendingIntent(
                            context,
                            offer,
                            action,
                        )
                        runCatching { pendingIntent.send() }
                    },
                    LayoutParams(0, dp(48), 1f),
                )
            }
        }
    }

    private fun actionButton(
        label: String,
        primary: Boolean,
        onPressed: () -> Unit,
    ): Button =
        Button(context).apply {
            text = label
            textSize = if (label == "SUBMIT BID") 11f else 12f
            isAllCaps = false
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(if (primary) NAVY else WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(12).toFloat()
                if (primary) {
                    setColor(GOLD)
                } else {
                    setColor(Color.TRANSPARENT)
                    setStroke(dp(1), Color.argb(130, 255, 255, 255))
                }
            }
            setOnClickListener { onPressed() }
        }

    private fun textView(
        sizeSp: Float,
        bold: Boolean = false,
        color: Int = WHITE,
    ): TextView = TextView(context).apply {
        textSize = sizeSp
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private val NAVY = Color.rgb(15, 25, 35)
        private val GOLD = Color.rgb(244, 185, 66)
        private val WHITE = Color.WHITE
        private val MUTED = Color.rgb(184, 193, 204)
    }
}
