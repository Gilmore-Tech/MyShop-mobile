package com.gilmoretech.myshopprovider

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.Executors

/**
 * Native foreground location worker. It keeps collecting after Android pauses
 * the Flutter isolate on screen lock and uploads only with a location-scoped,
 * exact-Online-session credential.
 */
class ProviderLocationService : Service(), LocationListener {
    companion object {
        const val ACTION_START = "com.gilmoretech.myshopprovider.location.START"
        const val ACTION_STOP = "com.gilmoretech.myshopprovider.location.STOP"
        const val ACTION_SET_APP_ACTIVE = "com.gilmoretech.myshopprovider.location.SET_APP_ACTIVE"
        const val EXTRA_ENDPOINT = "endpoint"
        const val EXTRA_CREDENTIAL = "credential"
        const val EXTRA_SESSION_ID = "onlineSessionId"
        const val EXTRA_EXPECTED_SESSION_ID = "expectedOnlineSessionId"
        const val EXTRA_APP_ACTIVE = "appActive"

        private const val PREFS = "provider_native_location"
        private const val CHANNEL_ID = "provider_online_location"
        private const val NOTIFICATION_ID = 42031
        private const val MIN_UPLOAD_INTERVAL_MS = 12_000L
        private const val MAX_ACCURACY_METERS = 100f

        fun hasPersistedConfiguration(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return !prefs.getString(EXTRA_ENDPOINT, null).isNullOrBlank() &&
                !prefs.getString(EXTRA_CREDENTIAL, null).isNullOrBlank() &&
                !prefs.getString(EXTRA_SESSION_ID, null).isNullOrBlank()
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var locationManager: LocationManager
    @Volatile private var endpoint: String? = null
    @Volatile private var credential: String? = null
    @Volatile private var sessionId: String? = null
    @Volatile private var lastUploadAt = 0L
    @Volatile private var uploadInFlight = false
    @Volatile private var appActive = false

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            val expected = intent.getStringExtra(EXTRA_EXPECTED_SESSION_ID)
            if (expected == null || expected == sessionId || expected == persistedSessionId()) {
                stopWorker()
                return START_NOT_STICKY
            }

            // A delayed stop from an older Flutter isolate must not strand a
            // newer Online session. Restore and continue the persisted exact
            // session instead of leaving an idle Service behind.
            restoreConfiguration()
            if (endpoint.isNullOrEmpty() || credential.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
                stopSelf()
                return START_NOT_STICKY
            }
            startForeground(NOTIFICATION_ID, buildNotification())
            applyLocationOwnership()
            return START_STICKY
        }

        if (intent?.action == ACTION_START) {
            endpoint = intent.getStringExtra(EXTRA_ENDPOINT)?.trim()
            credential = intent.getStringExtra(EXTRA_CREDENTIAL)?.trim()
            sessionId = intent.getStringExtra(EXTRA_SESSION_ID)?.trim()
            if (endpoint.isNullOrEmpty() || credential.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
                stopSelf()
                return START_NOT_STICKY
            }
            appActive = intent.getBooleanExtra(EXTRA_APP_ACTIVE, false)
            persistConfiguration()
        } else if (intent?.action == ACTION_SET_APP_ACTIVE) {
            appActive = intent.getBooleanExtra(EXTRA_APP_ACTIVE, false)
            restoreConfiguration()
        } else {
            restoreConfiguration()
        }

        if (endpoint.isNullOrEmpty() || credential.isNullOrEmpty() || sessionId.isNullOrEmpty()) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        applyLocationOwnership()
        return START_STICKY
    }

    private fun applyLocationOwnership() {
        if (appActive) {
            pauseLocationUpdates()
        } else {
            startLocationUpdates()
        }
    }

    private fun startLocationUpdates() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
        ) {
            stopWorker()
            return
        }
        // Repeated lifecycle signals must not register duplicate listeners.
        pauseLocationUpdates()
        runCatching {
            if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    5_000L,
                    0f,
                    this,
                )
            }
            if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    5_000L,
                    0f,
                    this,
                )
            }
        }.onFailure { Log.w("ProviderLocation", "location start failed", it) }
    }

    private fun pauseLocationUpdates() {
        runCatching { locationManager.removeUpdates(this) }
    }

    override fun onLocationChanged(location: Location) {
        val now = System.currentTimeMillis()
        if (location.accuracy < 0 || location.accuracy > MAX_ACCURACY_METERS) return
        if (now - location.time > 30_000L || location.time > now + 1_000L) return
        if (now - lastUploadAt < MIN_UPLOAD_INTERVAL_MS || uploadInFlight) return
        val target = endpoint ?: return
        val token = credential ?: return
        uploadInFlight = true
        executor.execute {
            try {
                val status = upload(target, token, location)
                if (status in 200..299) {
                    lastUploadAt = System.currentTimeMillis()
                } else if (status == 401 || status == 403 || status == 409) {
                    // Exact Online authority ended. Never keep a native worker
                    // alive in the hope of resurrecting it.
                    stopWorker()
                }
            } catch (error: Exception) {
                Log.w("ProviderLocation", "screen-off upload failed", error)
            } finally {
                uploadInFlight = false
            }
        }
    }

    private fun upload(target: String, token: String, location: Location): Int {
        val connection = URL(target).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.doOutput = true
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("X-MyShop-App", "provider")
        connection.setRequestProperty("X-MyShop-Platform", "android")
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        connection.setRequestProperty("X-MyShop-Version", packageInfo.versionName ?: "unknown")
        val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }
        connection.setRequestProperty("X-MyShop-Build", buildNumber)
        val payload = JSONObject()
            .put("credential", token)
            .put("latitude", location.latitude)
            .put("longitude", location.longitude)
            .put("accuracyMeters", location.accuracy.toDouble())
            .put("recordedAt", Instant.ofEpochMilli(location.time).toString())
        if (location.hasBearing()) payload.put("heading", location.bearing.toDouble())
        if (location.hasSpeed()) payload.put("speedKmh", location.speed * 3.6)
        connection.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
        val status = connection.responseCode
        runCatching {
            (if (status in 200..299) connection.inputStream else connection.errorStream)?.close()
        }
        connection.disconnect()
        return status
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder.setSmallIcon(com.gilmoretech.myshopprovider.R.drawable.ic_notification)
            .setContentTitle("MyShop Provider is Online")
            .setContentText("Location is active so you can receive nearby requests.")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Online location",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps provider location current while Online"
            setShowBadge(false)
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun persistConfiguration() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(EXTRA_ENDPOINT, endpoint)
            .putString(EXTRA_CREDENTIAL, credential)
            .putString(EXTRA_SESSION_ID, sessionId)
            .apply()
    }

    private fun restoreConfiguration() {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        endpoint = prefs.getString(EXTRA_ENDPOINT, null)
        credential = prefs.getString(EXTRA_CREDENTIAL, null)
        sessionId = prefs.getString(EXTRA_SESSION_ID, null)
    }

    private fun persistedSessionId(): String? =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(EXTRA_SESSION_ID, null)

    private fun stopWorker() {
        pauseLocationUpdates()
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        endpoint = null
        credential = null
        sessionId = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        pauseLocationUpdates()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onProviderEnabled(provider: String) = Unit
    override fun onProviderDisabled(provider: String) = Unit
    @Deprecated("Deprecated in API 29")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    override fun onBind(intent: Intent?): IBinder? = null
}
