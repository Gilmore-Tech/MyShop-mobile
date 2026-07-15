package com.gilmoretech.incoming_request_overlay

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class IncomingRequestOverlayPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var listeningSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        listeningSink?.let(OverlayActionEvents::detach)
        listeningSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            "canDrawOverlays" -> result.success(canDrawOverlays())
            "openOverlaySettings" -> result.success(openOverlaySettings())
            "showOffer" -> showOffer(call, result)
            "dismissOffer" -> dismissOffer(call, result)
            "dismissAll" -> {
                IncomingRequestOverlayService.requestDismissAll(applicationContext)
                result.success(null)
            }
            "drainPendingActions" -> result.success(
                PendingActionStore.peek(applicationContext).map(PendingOverlayAction::toMap),
            )
            "acknowledgeAction" -> acknowledgeAction(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        listeningSink?.let(OverlayActionEvents::detach)
        listeningSink = events
        OverlayActionEvents.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        listeningSink?.let(OverlayActionEvents::detach)
        listeningSink = null
    }

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(applicationContext)

    private fun openOverlaySettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:${applicationContext.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching {
            applicationContext.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun showOffer(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments as? Map<*, *>
        val offer = raw?.let(OfferPayload::fromMap)
        if (offer == null || offer.isExpired() || !canDrawOverlays()) {
            result.success(false)
            return
        }
        val started = runCatching {
            IncomingRequestOverlayService.show(applicationContext, offer)
            true
        }.getOrDefault(false)
        result.success(started)
    }

    private fun dismissOffer(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments as? Map<*, *>
        val offerId = raw?.get("offerId")?.toString()?.trim().orEmpty()
        val offerType = raw?.get("offerType")?.toString()?.trim().orEmpty()
        if (offerId.isNotEmpty() && offerType in setOf("ride", "job")) {
            IncomingRequestOverlayService.requestDismiss(
                applicationContext,
                offerType,
                offerId,
            )
        }
        result.success(null)
    }

    private fun acknowledgeAction(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments as? Map<*, *>
        val actionId = raw?.get("actionId")?.toString()?.trim().orEmpty()
        PendingActionStore.acknowledge(applicationContext, actionId)
        result.success(null)
    }

    companion object {
        private const val METHOD_CHANNEL =
            "com.gilmoretech.incoming_request_overlay/methods"
        private const val EVENT_CHANNEL =
            "com.gilmoretech.incoming_request_overlay/actions"
    }
}
