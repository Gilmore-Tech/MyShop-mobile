package com.gilmoretech.incoming_request_overlay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Memory-only, size-bounded loader for the single unlocked job thumbnail. */
internal object RemoteThumbnailLoader {
    private const val CONNECT_TIMEOUT_MILLIS = 2_500
    private const val READ_TIMEOUT_MILLIS = 3_000
    private const val MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024
    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun load(
        rawUrl: String,
        maxDimensionPx: Int,
        onResult: (Bitmap?) -> Unit,
    ): Future<*> = executor.submit {
        val bitmap = runCatching { download(rawUrl, maxDimensionPx) }.getOrNull()
        mainHandler.post { onResult(bitmap) }
    }

    private fun download(rawUrl: String, maxDimensionPx: Int): Bitmap? {
        val url = URL(rawUrl)
        // Never put private job media on a clear-text connection.
        if (!url.protocol.equals("https", ignoreCase = true)) return null
        val connection = (url.openConnection() as? HttpURLConnection) ?: return null
        return try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.useCaches = false
            connection.connect()
            if (connection.responseCode !in 200..299) return null
            val advertisedLength = connection.contentLengthLong
            if (advertisedLength > MAX_DOWNLOAD_BYTES) return null
            val bytes = connection.inputStream.use { input ->
                val output = ByteArrayOutputStream(
                    advertisedLength.takeIf { it in 1..MAX_DOWNLOAD_BYTES }?.toInt() ?: 32 * 1024,
                )
                val buffer = ByteArray(8 * 1024)
                var total = 0
                while (true) {
                    if (Thread.currentThread().isInterrupted) return null
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_DOWNLOAD_BYTES) return null
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            decodeBounded(bytes, maxDimensionPx.coerceAtLeast(1))
        } finally {
            connection.disconnect()
        }
    }

    private fun decodeBounded(bytes: ByteArray, maxDimensionPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sampleSize = 1
        while (bounds.outWidth / sampleSize > maxDimensionPx * 2 ||
            bounds.outHeight / sampleSize > maxDimensionPx * 2
        ) {
            sampleSize *= 2
        }
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }
}
