package com.gilmoretech.incoming_request_overlay

import android.annotation.SuppressLint
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import kotlin.math.min

class IncomingRequestOverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var keyguardManager: KeyguardManager
    private val handler = Handler(Looper.getMainLooper())
    private var currentOffer: OfferPayload? = null
    private val pendingOffers = linkedMapOf<String, OfferPayload>()
    private var cardView: OfferCardView? = null
    private var lastLockedState: Boolean? = null
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var privacyReceiverRegistered = false

    private val ticker = object : Runnable {
        override fun run() {
            val offer = currentOffer ?: return
            if (offer.isExpired()) {
                dismissCurrentAndAdvance()
                return
            }
            val locked = keyguardManager.isDeviceLocked
            if (locked != lastLockedState) {
                renderCard(offer, locked)
            } else {
                cardView?.updateCountdown()
            }
            handler.postDelayed(this, 1_000L)
        }
    }

    private val privacyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            currentOffer?.let { renderCard(it, keyguardManager.isDeviceLocked) }
        }
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        registerPrivacyReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()
        when (intent?.action) {
            ACTION_SHOW -> {
                val offer = OfferPayloadCodec.read(intent)
                if (!Settings.canDrawOverlays(this)) {
                    clearAllAndStop()
                } else if (offer != null && !offer.isExpired()) {
                    displayOffer(offer)
                } else if (currentOffer == null && pendingOffers.isEmpty()) {
                    stopForegroundAndSelf()
                }
            }
            ACTION_DISMISS -> {
                val expectedIdentity = identity(
                    intent.getStringExtra(OfferPayloadCodec.EXTRA_OFFER_TYPE),
                    intent.getStringExtra(OfferPayloadCodec.EXTRA_OFFER_ID),
                )
                if (expectedIdentity != null && currentOffer?.identity == expectedIdentity) {
                    dismissCurrentAndAdvance()
                } else if (expectedIdentity != null) {
                    pendingOffers.remove(expectedIdentity)
                } else if (currentOffer == null && pendingOffers.isEmpty()) {
                    stopForegroundAndSelf()
                }
            }
            ACTION_DISMISS_ALL -> clearAllAndStop()
            else -> if (currentOffer == null && pendingOffers.isEmpty()) stopForegroundAndSelf()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        pendingOffers.clear()
        removeCard()
        stopAlerting()
        if (privacyReceiverRegistered) {
            runCatching { unregisterReceiver(privacyReceiver) }
            privacyReceiverRegistered = false
        }
        super.onDestroy()
    }

    private fun displayOffer(offer: OfferPayload) {
        pendingOffers.remove(offer.identity)
        currentOffer?.takeIf {
            it.identity != offer.identity && !it.isExpired()
        }?.let {
            pendingOffers[it.identity] = it
            while (pendingOffers.size > MAX_PENDING_OFFERS) {
                pendingOffers.remove(pendingOffers.keys.first())
            }
        }
        activateOffer(offer)
    }

    private fun activateOffer(offer: OfferPayload) {
        currentOffer = offer
        handler.removeCallbacks(ticker)
        stopAlerting()
        renderCard(offer, keyguardManager.isDeviceLocked)
        acquireWakeLock(offer)
        startAlerting()
        handler.post(ticker)
    }

    @Suppress("DEPRECATION")
    private fun renderCard(offer: OfferPayload, isLocked: Boolean) {
        removeCard()
        lastLockedState = isLocked
        val card = OfferCardView(
            context = this,
            offer = offer,
            isLocked = isLocked,
            onUnlockRequested = ::requestUnlock,
        ).also {
            it.updateCountdown()
        }
        val horizontalMargin = dp(12)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = dp(36)
            width = resources.displayMetrics.widthPixels - (horizontalMargin * 2)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        val added = runCatching {
            windowManager.addView(card, params)
            true
        }.getOrDefault(false)
        if (added) {
            cardView = card
        } else {
            clearAllAndStop()
        }
    }

    private fun removeCard() {
        cardView?.let { view ->
            runCatching {
                if (view.windowToken != null || view.isAttachedToWindow) {
                    windowManager.removeViewImmediate(view)
                }
            }
        }
        cardView = null
    }

    private fun requestUnlock() {
        if (!keyguardManager.isDeviceLocked) {
            currentOffer?.let { renderCard(it, false) }
            return
        }
        val credentialIntent = keyguardManager.createConfirmDeviceCredentialIntent(
            getString(R.string.incoming_request_overlay_unlock_title),
            getString(R.string.incoming_request_overlay_unlock_description),
        ) ?: return
        credentialIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { startActivity(credentialIntent) }
    }

    private fun dismissCurrentAndAdvance() {
        currentOffer = null
        lastLockedState = null
        handler.removeCallbacks(ticker)
        removeCard()
        stopAlerting()
        val now = System.currentTimeMillis()
        pendingOffers.entries.removeAll { it.value.isExpired(now) }
        val next = pendingOffers.entries.lastOrNull()?.let { entry ->
            pendingOffers.remove(entry.key)
            entry.value
        }
        if (next != null) {
            activateOffer(next)
            return
        }
        stopForegroundAndSelf()
    }

    private fun clearAllAndStop() {
        pendingOffers.clear()
        currentOffer = null
        lastLockedState = null
        handler.removeCallbacks(ticker)
        removeCard()
        stopAlerting()
        stopForegroundAndSelf()
    }

    private fun ensureForeground() {
        createNotificationChannel()
        val notification = serviceNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.incoming_request_overlay_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.incoming_request_overlay_channel_description)
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun serviceNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launchIntent?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            PendingIntent.getActivity(this, NOTIFICATION_ID, it, pendingFlags)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(getString(R.string.incoming_request_overlay_service_title))
            .setContentText(getString(R.string.incoming_request_overlay_service_body))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(contentIntent)
            .build()
    }

    @SuppressLint("WakelockTimeout")
    @Suppress("DEPRECATION")
    private fun acquireWakeLock(offer: OfferPayload) {
        releaseWakeLock()
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "$packageName:incoming-request-overlay",
        ).apply {
            setReferenceCounted(false)
            val remaining = (offer.expiresAtMillis - System.currentTimeMillis()).coerceAtLeast(1_000L)
            acquire(min(remaining, SCREEN_WAKE_MILLIS))
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) runCatching { it.release() } }
        wakeLock = null
    }

    private fun startAlerting() {
        requestAudioFocus()
        mediaPlayer = runCatching {
            val descriptor = resources.openRawResourceFd(R.raw.incoming_request)
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(
                    descriptor.fileDescriptor,
                    descriptor.startOffset,
                    descriptor.length,
                )
                descriptor.close()
                isLooping = true
                prepare()
                start()
            }
        }.getOrNull()

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0L, 450L, 850L)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun stopAlerting() {
        runCatching { mediaPlayer?.stop() }
        runCatching { mediaPlayer?.release() }
        mediaPlayer = null
        runCatching { vibrator?.cancel() }
        vibrator = null
        abandonAudioFocus()
        releaseWakeLock()
    }

    private fun requestAudioFocus() {
        val audioManager = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setOnAudioFocusChangeListener { }
                .build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_RING,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
    }

    private fun abandonAudioFocus() {
        val audioManager = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
        audioFocusRequest = null
    }

    private fun registerPrivacyReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(privacyReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(privacyReceiver, filter)
        }
        privacyReceiverRegistered = true
    }

    private fun stopForegroundAndSelf() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val ACTION_SHOW =
            "com.gilmoretech.incoming_request_overlay.SHOW"
        private const val ACTION_DISMISS =
            "com.gilmoretech.incoming_request_overlay.DISMISS"
        private const val ACTION_DISMISS_ALL =
            "com.gilmoretech.incoming_request_overlay.DISMISS_ALL"
        private const val NOTIFICATION_CHANNEL_ID = "incoming_request_overlay_service_v1"
        private const val NOTIFICATION_ID = 774_310
        private const val SCREEN_WAKE_MILLIS = 10_000L
        private const val MAX_PENDING_OFFERS = 5

        fun show(context: Context, offer: OfferPayload) {
            val intent = OfferPayloadCodec.put(
                Intent(context, IncomingRequestOverlayService::class.java).setAction(ACTION_SHOW),
                offer,
            )
            start(context, intent)
        }

        fun requestDismiss(context: Context, offerType: String, offerId: String) {
            val intent = Intent(context, IncomingRequestOverlayService::class.java)
                .setAction(ACTION_DISMISS)
                .putExtra(OfferPayloadCodec.EXTRA_OFFER_TYPE, offerType)
                .putExtra(OfferPayloadCodec.EXTRA_OFFER_ID, offerId)
            start(context, intent)
        }

        fun requestDismissAll(context: Context) {
            start(
                context,
                Intent(context, IncomingRequestOverlayService::class.java)
                    .setAction(ACTION_DISMISS_ALL),
            )
        }

        private fun start(context: Context, intent: Intent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        private fun identity(offerType: String?, offerId: String?): String? {
            val type = offerType?.trim().orEmpty()
            val id = offerId?.trim().orEmpty()
            if (type !in setOf("ride", "job") || id.isEmpty()) return null
            return "$type:$id"
        }
    }
}
