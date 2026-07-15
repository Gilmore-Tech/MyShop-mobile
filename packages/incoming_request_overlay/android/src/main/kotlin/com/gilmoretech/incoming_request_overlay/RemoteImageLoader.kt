package com.gilmoretech.incoming_request_overlay

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.Future
import javax.net.ssl.HttpsURLConnection

/**
 * Memory-only, size-bounded loader for short-lived offer imagery.
 *
 * Redirects are followed manually so an HTTPS URL cannot silently downgrade or
 * escape to a different host. The overlay intentionally has no disk cache: job
 * photos and route previews must disappear with the offer card.
 */
internal object RemoteImageLoader {
    private const val CONNECT_TIMEOUT_MILLIS = 2_500
    private const val READ_TIMEOUT_MILLIS = 3_000
    private const val MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024
    private const val MAX_REDIRECTS = 3
    private const val MAX_SOURCE_DIMENSION_PX = 16_384
    private const val MAX_SOURCE_PIXELS = 40_000_000L
    private const val MAX_DECODE_DIMENSION_PX = 2_048

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun load(
        rawUrl: String,
        maxDimensionPx: Int,
        onResult: (Bitmap?) -> Unit,
    ): Future<*> = executor.submit {
        val bitmap = runCatching { download(rawUrl, maxDimensionPx) }.getOrNull()
        if (!Thread.currentThread().isInterrupted) {
            mainHandler.post { onResult(bitmap) }
        }
    }

    private fun download(rawUrl: String, maxDimensionPx: Int): Bitmap? {
        var currentUrl = RemoteImageUrlPolicy.parse(rawUrl) ?: return null
        var redirectCount = 0

        while (true) {
            if (Thread.currentThread().isInterrupted) return null
            val connection = currentUrl.openConnection() as? HttpsURLConnection ?: return null
            connection.instanceFollowRedirects = false
            connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
            connection.readTimeout = READ_TIMEOUT_MILLIS
            connection.useCaches = false
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept", "image/*")

            try {
                connection.connect()
                val responseCode = connection.responseCode
                if (responseCode in REDIRECT_CODES) {
                    if (redirectCount >= MAX_REDIRECTS) return null
                    val location = connection.getHeaderField("Location") ?: return null
                    val nextUrl = runCatching { URL(currentUrl, location) }.getOrNull() ?: return null
                    if (!RemoteImageUrlPolicy.isAllowedRedirect(currentUrl, nextUrl)) return null
                    currentUrl = nextUrl
                    redirectCount += 1
                    continue
                }
                if (responseCode !in 200..299) return null

                val mimeType = connection.contentType
                    ?.substringBefore(';')
                    ?.trim()
                    ?.lowercase(Locale.US)
                if (mimeType == null || !mimeType.startsWith("image/")) return null

                val advertisedLength = connection.getHeaderField("Content-Length")
                    ?.trim()
                    ?.toLongOrNull()
                    ?: -1L
                if (advertisedLength > MAX_DOWNLOAD_BYTES) return null

                val bytes = connection.inputStream.use { input ->
                    val initialCapacity = advertisedLength
                        .takeIf { it in 1..MAX_DOWNLOAD_BYTES }
                        ?.toInt()
                        ?: 32 * 1024
                    val output = ByteArrayOutputStream(initialCapacity)
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
                return decodeBounded(
                    bytes,
                    maxDimensionPx.coerceIn(1, MAX_DECODE_DIMENSION_PX),
                )
            } finally {
                connection.disconnect()
            }
        }
    }

    private fun decodeBounded(bytes: ByteArray, maxDimensionPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        if (bounds.outWidth > MAX_SOURCE_DIMENSION_PX ||
            bounds.outHeight > MAX_SOURCE_DIMENSION_PX ||
            bounds.outWidth.toLong() * bounds.outHeight.toLong() > MAX_SOURCE_PIXELS
        ) {
            return null
        }

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

    private val REDIRECT_CODES = setOf(
        HttpsURLConnection.HTTP_MOVED_PERM,
        HttpsURLConnection.HTTP_MOVED_TEMP,
        HttpsURLConnection.HTTP_SEE_OTHER,
        307,
        308,
    )
}

/** Pure URL checks kept separate so the JVM unit suite can exercise them. */
internal object RemoteImageUrlPolicy {
    private const val MAX_URL_LENGTH = 4_096

    fun parse(rawUrl: String): URL? {
        val normalized = rawUrl.trim()
        if (normalized.isEmpty() || normalized.length > MAX_URL_LENGTH) return null
        val url = runCatching { URL(normalized) }.getOrNull() ?: return null
        return url.takeIf(::isSafeHttpsUrl)
    }

    fun isAllowedRedirect(from: URL, to: URL): Boolean {
        if (!isSafeHttpsUrl(from) || !isSafeHttpsUrl(to)) return false
        return normalizedHost(from) == normalizedHost(to) && effectivePort(from) == effectivePort(to)
    }

    private fun isSafeHttpsUrl(url: URL): Boolean {
        if (!url.protocol.equals("https", ignoreCase = true)) return false
        if (url.host.isBlank() || url.userInfo != null) return false
        return url.port == -1 || url.port == DEFAULT_HTTPS_PORT
    }

    private fun normalizedHost(url: URL): String =
        url.host.trimEnd('.').lowercase(Locale.US)

    private fun effectivePort(url: URL): Int =
        if (url.port == -1) DEFAULT_HTTPS_PORT else url.port

    private const val DEFAULT_HTTPS_PORT = 443
}
