package com.gilmoretech.incoming_request_overlay

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.concurrent.Future
import kotlin.math.max
import kotlin.math.min

/** A bounded, scrollable native offer surface suitable for an overlay window. */
internal class OfferCardView(
    context: Context,
    private val offer: OfferPayload,
    private val isLocked: Boolean,
    private val maxHeightPx: Int,
    private val onUnlockRequested: () -> Unit,
) : FrameLayout(context) {
    private val countdown = textView(sizeSp = 14f, bold = true, color = GOLD)
    private val imageFutures = mutableListOf<Future<*>>()
    private val imageViews = mutableListOf<ImageView>()
    private val bodyScroll: ScrollView
    private val actionFooter: View
    private var released = false

    init {
        elevation = dp(16).toFloat()
        background = roundedBackground(
            color = NAVY,
            radiusDp = 24,
            strokeColor = Color.argb(70, 255, 255, 255),
        )
        clipToOutline = true

        val safeTitle = if (offer.offerType == "ride") {
            context.getString(R.string.incoming_request_overlay_ride_title)
        } else {
            context.getString(R.string.incoming_request_overlay_job_title)
        }
        contentDescription = if (isLocked) safeTitle else offer.title

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(8))
            addView(header())
            addSection(
                textView(sizeSp = 20f, bold = true).apply {
                    text = if (isLocked) safeTitle else offer.title
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                },
                topMarginDp = 10,
            )
            addSection(metricsPanel(), topMarginDp = 12)

            if (isLocked) {
                addSection(lockedNotice(), topMarginDp = 12)
            } else {
                addUnlockedSections(this)
            }
        }

        bodyScroll = ScrollView(context).apply {
            isFillViewport = false
            isVerticalScrollBarEnabled = true
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            addView(
                content,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT),
            )
        }
        actionFooter = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(8), dp(18), dp(18))
            addView(
                actions(),
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(
                bodyScroll,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                actionFooter,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    fun updateCountdown(nowMillis: Long = System.currentTimeMillis()) {
        val remainingMillis = max(0L, offer.expiresAtMillis - nowMillis)
        val seconds = (remainingMillis + 999L) / 1_000L
        countdown.text = context.getString(
            R.string.incoming_request_overlay_countdown,
            seconds,
        )
        countdown.setTextColor(if (seconds <= 10L) DANGER else GOLD)
        countdown.contentDescription = context.resources.getQuantityString(
            R.plurals.incoming_request_overlay_seconds_remaining,
            seconds.toInt(),
            seconds,
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val parentLimit = when (MeasureSpec.getMode(heightMeasureSpec)) {
            MeasureSpec.UNSPECIFIED -> maxHeightPx
            else -> min(MeasureSpec.getSize(heightMeasureSpec), maxHeightPx)
        }.coerceAtLeast(dp(180))

        // Measure the action tray first, then give only the remaining height to
        // the scrolling details. Offer actions therefore remain reachable even
        // on compact screens or when a job description is long.
        val availableWidth = MeasureSpec.getSize(widthMeasureSpec).coerceAtLeast(1)
        val exactWidth = MeasureSpec.makeMeasureSpec(availableWidth, MeasureSpec.EXACTLY)
        actionFooter.measure(
            exactWidth,
            MeasureSpec.makeMeasureSpec(parentLimit, MeasureSpec.AT_MOST),
        )
        val bodyLimit = (parentLimit - actionFooter.measuredHeight).coerceAtLeast(dp(48))
        bodyScroll.measure(
            exactWidth,
            MeasureSpec.makeMeasureSpec(bodyLimit, MeasureSpec.AT_MOST),
        )
        bodyScroll.layoutParams = bodyScroll.layoutParams.apply {
            height = bodyScroll.measuredHeight.coerceAtMost(bodyLimit)
        }
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(parentLimit, MeasureSpec.AT_MOST),
        )
    }

    override fun onDetachedFromWindow() {
        released = true
        imageFutures.forEach { it.cancel(true) }
        imageFutures.clear()
        imageViews.forEach { it.setImageDrawable(null) }
        imageViews.clear()
        super.onDetachedFromWindow()
    }

    private fun header(): View = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL

        val marker = View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(GOLD)
            }
        }
        addView(marker, LinearLayout.LayoutParams(dp(9), dp(9)).apply {
            marginEnd = dp(8)
        })
        addView(
            textView(sizeSp = 12f, bold = true, color = GOLD).apply {
                text = if (offer.offerType == "ride") {
                    context.getString(R.string.incoming_request_overlay_ride_badge)
                } else {
                    context.getString(R.string.incoming_request_overlay_job_badge)
                }
                letterSpacing = 0.08f
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        countdown.apply {
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = roundedBackground(
                color = Color.argb(36, 244, 185, 66),
                radiusDp = 14,
                strokeColor = Color.argb(70, 244, 185, 66),
            )
        }
        addView(countdown)
    }

    private fun metricsPanel(): View = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(14), dp(12), dp(14), dp(12))
        background = roundedBackground(PANEL, radiusDp = 16)

        if (offer.offerType == "job" && !offer.category.isNullOrBlank()) {
            addView(textView(sizeSp = 12f, bold = true, color = GOLD).apply {
                text = offer.category
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
        }

        offer.amount?.takeIf { it.isNotBlank() }?.let { amount ->
            addView(textView(sizeSp = if (amount.length > 22) 20f else 27f, bold = true).apply {
                text = amount
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                if (offer.offerType == "job" && !offer.category.isNullOrBlank()) {
                    setPadding(0, dp(5), 0, 0)
                }
            })
            addView(textView(sizeSp = 11f, bold = true, color = MUTED).apply {
                text = offer.amountLabel ?: pricingCaption(amount)
                letterSpacing = 0.06f
                setPadding(0, dp(2), 0, 0)
            })
            offer.pricingSummary?.takeIf { it.isNotBlank() }?.let { summary ->
                addView(textView(sizeSp = 12f, bold = true, color = MUTED).apply {
                    text = summary
                    maxLines = 3
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(8), 0, 0)
                })
            }
        }

        val metrics = listOfNotNull(
            offer.distance?.takeIf { it.isNotBlank() }?.let {
                context.getString(R.string.incoming_request_overlay_distance_metric, it)
            },
            offer.duration?.takeIf { it.isNotBlank() }?.let {
                context.getString(R.string.incoming_request_overlay_duration_metric, it)
            },
        )
        if (metrics.isNotEmpty()) {
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.START
                setPadding(0, dp(10), 0, 0)
                metrics.forEachIndexed { index, value ->
                    if (index > 0) addView(View(context), LinearLayout.LayoutParams(dp(8), 1))
                    addView(metricChip(value))
                }
            })
        }
    }

    private fun pricingCaption(amount: String): String = when {
        offer.offerType == "ride" ->
            context.getString(R.string.incoming_request_overlay_estimated_fare)
        amount.startsWith("Minimum ", ignoreCase = true) ->
            context.getString(R.string.incoming_request_overlay_minimum_bid)
        else -> context.getString(R.string.incoming_request_overlay_quote)
    }

    private fun metricChip(value: String): View = textView(sizeSp = 12f, bold = true).apply {
        text = value
        setPadding(dp(10), dp(6), dp(10), dp(6))
        background = roundedBackground(
            color = Color.argb(36, 255, 255, 255),
            radiusDp = 14,
        )
    }

    private fun lockedNotice(): View = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(13), dp(11), dp(13), dp(11))
        background = roundedBackground(
            color = Color.argb(28, 255, 255, 255),
            radiusDp = 14,
            strokeColor = Color.argb(42, 255, 255, 255),
        )
        addView(textView(sizeSp = 13f, bold = true).apply {
            text = context.getString(R.string.incoming_request_overlay_private_details)
        })
        addView(textView(sizeSp = 13f, color = MUTED).apply {
            text = context.getString(R.string.incoming_request_overlay_locked)
            setPadding(0, dp(3), 0, 0)
        })
    }

    private fun addUnlockedSections(content: LinearLayout) {
        if (offer.offerType == "job") {
            jobPhoto()?.let { content.addSection(it, topMarginDp = 12) }
        }
        mapPreview()?.let { content.addSection(it, topMarginDp = 12) }

        if (offer.offerType == "ride") {
            rideRoute()?.let { content.addSection(it, topMarginDp = 12) }
            informationPanel(
                listOf(
                    context.getString(R.string.incoming_request_overlay_passenger) to offer.customerName,
                ),
            )?.let { content.addSection(it, topMarginDp = 12) }
        } else {
            informationPanel(
                listOf(
                    context.getString(R.string.incoming_request_overlay_client) to offer.customerName,
                    context.getString(R.string.incoming_request_overlay_location) to offer.location,
                    context.getString(R.string.incoming_request_overlay_request) to offer.description,
                ),
                descriptionLines = 3,
            )?.let { content.addSection(it, topMarginDp = 12) }
        }
    }

    private fun mapPreview(): View? {
        val url = offer.mapPreviewUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val label = if (offer.offerType == "ride") {
            context.getString(R.string.incoming_request_overlay_route_preview)
        } else {
            context.getString(R.string.incoming_request_overlay_location_preview)
        }
        return remoteImage(
            url = url,
            heightDp = 132,
            contentDescription = label,
            loadingLabel = context.getString(R.string.incoming_request_overlay_loading_preview),
            failureLabel = context.getString(R.string.incoming_request_overlay_preview_unavailable),
            scaleType = ImageView.ScaleType.FIT_CENTER,
        )
    }

    private fun jobPhoto(): View? {
        val url = offer.photoUrl?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return remoteImage(
            url = url,
            heightDp = 104,
            contentDescription = context.getString(R.string.incoming_request_overlay_job_photo),
            loadingLabel = context.getString(R.string.incoming_request_overlay_loading_photo),
            failureLabel = context.getString(R.string.incoming_request_overlay_photo_unavailable),
            scaleType = ImageView.ScaleType.CENTER_CROP,
        )
    }

    private fun remoteImage(
        url: String,
        heightDp: Int,
        contentDescription: String,
        loadingLabel: String,
        failureLabel: String,
        scaleType: ImageView.ScaleType,
    ): View {
        val frame = FrameLayout(context).apply {
            background = roundedBackground(
                color = PANEL,
                radiusDp = 15,
                strokeColor = Color.argb(42, 255, 255, 255),
            )
            clipToOutline = true
        }
        val image = ImageView(context).apply {
            this.scaleType = scaleType
            this.contentDescription = contentDescription
        }
        val status = textView(sizeSp = 12f, bold = true, color = MUTED).apply {
            text = loadingLabel
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(8), dp(16), dp(8))
        }
        frame.addView(
            image,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp(heightDp),
            ),
        )
        frame.addView(
            status,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dp(heightDp),
            ),
        )
        imageViews += image
        imageFutures += RemoteImageLoader.load(url, dp(360)) { bitmap ->
            if (released) return@load
            if (bitmap == null) {
                status.text = failureLabel
            } else {
                image.setImageBitmap(bitmap)
                status.visibility = View.GONE
            }
        }
        return frame
    }

    private fun rideRoute(): View? {
        val pickup = offer.pickup?.takeIf { it.isNotBlank() }
        val destination = offer.destination?.takeIf { it.isNotBlank() }
        if (pickup == null && destination == null) return null

        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(13), dp(14), dp(13))
            background = roundedBackground(PANEL, radiusDp = 16)

            pickup?.let {
                addView(
                    routeStop(
                        context.getString(R.string.incoming_request_overlay_pickup),
                        it,
                        GOLD,
                    ),
                )
            }
            if (pickup != null && destination != null) {
                addView(View(context).apply {
                    setBackgroundColor(Color.argb(90, 255, 255, 255))
                }, LinearLayout.LayoutParams(dp(2), dp(14)).apply {
                    marginStart = dp(4)
                })
            }
            destination?.let {
                addView(
                    routeStop(
                        context.getString(R.string.incoming_request_overlay_destination),
                        it,
                        WHITE,
                    ),
                )
            }
        }
    }

    private fun routeStop(label: String, value: String, markerColor: Int): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(markerColor)
                }
            }, LinearLayout.LayoutParams(dp(10), dp(10)).apply {
                topMargin = dp(5)
                marginEnd = dp(11)
            })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(textView(sizeSp = 10f, bold = true, color = MUTED).apply {
                    text = label
                    letterSpacing = 0.06f
                })
                addView(textView(sizeSp = 14f).apply {
                    text = value
                    maxLines = 2
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(2), 0, 0)
                })
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

    private fun informationPanel(
        details: List<Pair<String, String?>>,
        descriptionLines: Int = 1,
    ): View? {
        val visibleDetails = details.filter { !it.second.isNullOrBlank() }
        if (visibleDetails.isEmpty()) return null
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(10))
            background = roundedBackground(PANEL, radiusDp = 16)
            visibleDetails.forEachIndexed { index, (label, value) ->
                if (index > 0) {
                    addView(View(context).apply {
                        setBackgroundColor(Color.argb(25, 255, 255, 255))
                    }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply {
                        topMargin = dp(8)
                        bottomMargin = dp(8)
                    })
                }
                addView(detailRow(label, value.orEmpty(), if (index == visibleDetails.lastIndex) descriptionLines else 1))
            }
        }
    }

    private fun detailRow(label: String, value: String, maxLines: Int): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            addView(textView(sizeSp = 12f, bold = true, color = MUTED).apply {
                text = label
            }, LinearLayout.LayoutParams(dp(82), LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(textView(sizeSp = 14f).apply {
                text = value
                this.maxLines = maxLines
                ellipsize = TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

    private fun actions(): View {
        if (isLocked) {
            return actionButton(
                context.getString(R.string.incoming_request_overlay_unlock_action),
                ButtonStyle.PRIMARY,
                onUnlockRequested,
            )
        }

        val primaryLabel: String
        val primaryAction: String
        val viewLabel: String
        val viewAction: String
        val skipAction: String
        if (offer.offerType == "ride") {
            primaryLabel = context.getString(R.string.incoming_request_overlay_accept_ride)
            primaryAction = "ride_accept"
            viewLabel = context.getString(R.string.incoming_request_overlay_view_details)
            viewAction = "ride_view"
            skipAction = "ride_skip"
        } else {
            primaryLabel = context.getString(R.string.incoming_request_overlay_submit_bid)
            primaryAction = "job_bid"
            viewLabel = context.getString(R.string.incoming_request_overlay_view_job)
            viewAction = "job_view"
            skipAction = "job_skip"
        }

        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(
                actionButton(primaryLabel, ButtonStyle.PRIMARY) { sendAction(primaryAction) },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(54)),
            )
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                addView(
                    actionButton(viewLabel, ButtonStyle.SECONDARY) { sendAction(viewAction) },
                    LinearLayout.LayoutParams(0, dp(48), 1f),
                )
                addView(View(context), LinearLayout.LayoutParams(dp(8), 1))
                addView(
                    actionButton(
                        context.getString(R.string.incoming_request_overlay_skip),
                        ButtonStyle.TERTIARY,
                    ) { sendAction(skipAction) },
                    LinearLayout.LayoutParams(0, dp(48), 1f),
                )
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            })
        }
    }

    private fun sendAction(action: String) {
        val pendingIntent = IncomingRequestActionReceiver.pendingIntent(context, offer, action)
        runCatching { pendingIntent.send() }
    }

    private fun actionButton(
        label: String,
        style: ButtonStyle,
        onPressed: () -> Unit,
    ): Button = Button(context).apply {
        text = label
        contentDescription = label
        textSize = 13f
        isAllCaps = false
        minHeight = 0
        minWidth = 0
        stateListAnimator = null
        setTypeface(typeface, Typeface.BOLD)
        setTextColor(
            when (style) {
                ButtonStyle.PRIMARY -> NAVY
                ButtonStyle.SECONDARY -> WHITE
                ButtonStyle.TERTIARY -> MUTED
            },
        )
        background = when (style) {
            ButtonStyle.PRIMARY -> roundedBackground(GOLD, radiusDp = 14)
            ButtonStyle.SECONDARY -> roundedBackground(
                color = Color.argb(30, 255, 255, 255),
                radiusDp = 14,
                strokeColor = Color.argb(95, 255, 255, 255),
            )
            ButtonStyle.TERTIARY -> roundedBackground(
                color = Color.TRANSPARENT,
                radiusDp = 14,
            )
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
        includeFontPadding = false
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun LinearLayout.addSection(view: View, topMarginDp: Int) {
        addView(
            view,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(topMarginDp)
            },
        )
    }

    private fun roundedBackground(
        color: Int,
        radiusDp: Int,
        strokeColor: Int? = null,
    ): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(radiusDp).toFloat()
        setColor(color)
        strokeColor?.let { setStroke(dp(1), it) }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private enum class ButtonStyle { PRIMARY, SECONDARY, TERTIARY }

    companion object {
        private val NAVY = Color.rgb(13, 24, 34)
        private val PANEL = Color.rgb(25, 38, 50)
        private val GOLD = Color.rgb(244, 185, 66)
        private val WHITE = Color.WHITE
        private val MUTED = Color.rgb(184, 193, 204)
        private val DANGER = Color.rgb(255, 117, 117)
    }
}
