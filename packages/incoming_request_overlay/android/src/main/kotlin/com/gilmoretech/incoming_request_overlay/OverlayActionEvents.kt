package com.gilmoretech.incoming_request_overlay

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

internal object OverlayActionEvents {
    @Volatile
    private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(eventSink: EventChannel.EventSink) {
        sink = eventSink
    }

    fun detach(expectedSink: EventChannel.EventSink) {
        if (sink === expectedSink) sink = null
    }

    fun emit(action: PendingOverlayAction) {
        mainHandler.post { sink?.success(action.toMap()) }
    }
}
