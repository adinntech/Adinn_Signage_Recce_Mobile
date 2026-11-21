package com.example.signage_recce.ar

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.ar.core.ArCoreApk
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Flutter ⇄ ARCore bridge.
 * * Method channel `adinn/ar`: availability, install, placement, transform,
 *   capture.
 * * Event channel `adinn/ar/events`: ready, tracking, planes, anchorLost,
 *   error.
 * * Platform view `adinn/ar_view`: the camera AR surface.
 */
class ArBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var current: ArPlatformView? = null

    init {
        MethodChannel(messenger, "adinn/ar").setMethodCallHandler(this)
        EventChannel(messenger, "adinn/ar/events").setStreamHandler(this)
    }

    val viewFactory: PlatformViewFactory =
        object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
                ArPlatformView(activity, args as? Map<*, *> ?: emptyMap<String, Any?>(), this@ArBridge)
        }

    /** Views covered by a newer AR view (paused, anchors kept). */
    private val covered = ArrayDeque<ArPlatformView>()

    /**
     * Only one ARCore session may use the camera: a new view pauses the
     * current one (instead of destroying it) and the covered view resumes
     * when the new one closes.
     */
    internal fun attach(view: ArPlatformView) {
        val previous = current
        if (previous != null && previous !== view && !previous.isDisposed) {
            previous.suspend()
            covered.addLast(previous)
        }
        current = view
    }

    internal fun detach(view: ArPlatformView) {
        covered.remove(view)
        if (current !== view) return
        current = null
        while (covered.isNotEmpty()) {
            val next = covered.removeLast()
            if (next.isDisposed) continue
            current = next
            next.unsuspend()
            break
        }
    }

    private fun str(call: MethodCall, key: String): String? = call.argument<String>(key)

    private fun float(call: MethodCall, key: String, fallback: Float): Float =
        (call.argument<Number>(key) ?: fallback).toFloat()

    internal fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    internal fun emitError(code: String, message: String) =
        emit(mapOf("type" to "error", "code" to code, "message" to message))

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> checkAvailability(result, 0)
            "requestInstall" -> requestInstall(result)
            "placeAt" -> {
                val view = current ?: return result.success(mapOf("placed" to false, "reason" to "no_session"))
                val x = (call.argument<Number>("x") ?: 0.5).toFloat()
                val y = (call.argument<Number>("y") ?: 0.5).toFloat()
                val manual = call.argument<Boolean>("manual") ?: false
                view.renderer.queueTap(x, y, manual) { res -> main.post { result.success(res) } }
            }
            "setTransform" -> {
                current?.renderer?.let { r ->
                    r.userYaw = (call.argument<Number>("yaw") ?: 0).toFloat()
                    r.userScale = (call.argument<Number>("scale") ?: 1).toFloat().coerceIn(0.05f, 20f)
                    r.offsetX = (call.argument<Number>("x") ?: 0).toFloat()
                    r.offsetY = (call.argument<Number>("y") ?: 0).toFloat()
                    r.offsetZ = (call.argument<Number>("z") ?: 0).toFloat()
                }
                result.success(null)
            }
            "removePlacement" -> {
                current?.renderer?.requestRemove()
                result.success(null)
            }
            "setPlanesVisible" -> {
                current?.renderer?.planesVisible = call.argument<Boolean>("visible") ?: true
                result.success(null)
            }
            "setModel" -> {
                val model = call.argument<Map<*, *>>("model")
                val ok = model != null && current?.applyModel(model) == true
                result.success(ok)
            }
            "capture" -> {
                val view = current ?: return result.error("capture", "AR session is not running", null)
                view.renderer.requestCapture { bytes, error ->
                    main.post {
                        if (bytes != null) result.success(bytes) else result.error("capture", error, null)
                    }
                }
            }
            // --- Multi-object scene ------------------------------------
            "registerModel" -> {
                val view = current ?: return result.success(false)
                val key = str(call, "key") ?: return result.success(false)
                val map = call.argument<Map<*, *>>("model") ?: return result.success(false)
                val data = try {
                    ModelData.fromMap(map)
                } catch (e: Exception) {
                    return result.success(false)
                }
                view.renderer.registerModel(key, data)
                result.success(true)
            }
            "placeObject" -> {
                val view = current ?: return result.success(mapOf("placed" to false, "reason" to "no_session"))
                val id = str(call, "id") ?: return result.success(mapOf("placed" to false, "reason" to "bad_args"))
                val key = str(call, "key") ?: return result.success(mapOf("placed" to false, "reason" to "bad_args"))
                view.renderer.queuePlaceObject(
                    id,
                    key,
                    float(call, "x", 0.5f),
                    float(call, "y", 0.5f),
                    call.argument<Boolean>("manual") ?: false,
                ) { res -> main.post { result.success(res) } }
            }
            "anchorObject" -> {
                val view = current ?: return result.success(mapOf("placed" to false, "reason" to "no_session"))
                val id = str(call, "id") ?: return result.success(mapOf("placed" to false, "reason" to "bad_args"))
                val key = str(call, "key") ?: return result.success(mapOf("placed" to false, "reason" to "bad_args"))
                val pose = call.argument<List<*>>("pose")?.mapNotNull { (it as? Number)?.toFloat() }?.toFloatArray()
                if (pose == null || pose.size != 7) {
                    return result.success(mapOf("placed" to false, "reason" to "bad_pose"))
                }
                view.renderer.queueAnchorObject(id, key, pose, str(call, "surface") ?: "horizontal") { res ->
                    main.post { result.success(res) }
                }
            }
            "setObjectTransform" -> {
                val id = str(call, "id")
                if (id != null) {
                    current?.renderer?.setObjectTransform(
                        id,
                        float(call, "x", 0f),
                        float(call, "y", 0f),
                        float(call, "z", 0f),
                        float(call, "yaw", 0f),
                        float(call, "roll", 0f),
                        float(call, "scale", 1f),
                    )
                }
                result.success(null)
            }
            "setObjectVisible" -> {
                val id = str(call, "id")
                if (id != null) current?.renderer?.setObjectVisible(id, call.argument<Boolean>("visible") ?: true)
                result.success(null)
            }
            "selectObject" -> {
                current?.renderer?.selectObject(str(call, "id"))
                result.success(null)
            }
            "removeObject" -> {
                val id = str(call, "id")
                if (id != null) current?.renderer?.removeObject(id)
                result.success(null)
            }
            "hitTestObject" -> {
                val view = current ?: return result.success(null)
                view.renderer.queueHitTest(float(call, "x", 0.5f), float(call, "y", 0.5f)) { id ->
                    main.post { result.success(id) }
                }
            }
            "setPlacementIndicator" -> {
                current?.renderer?.setPlacementIndicator(
                    call.argument<Boolean>("active") ?: false,
                    call.argument<Boolean>("vertical") ?: false,
                )
                result.success(null)
            }
            "pause" -> {
                current?.pauseSession()
                result.success(null)
            }
            "resume" -> {
                current?.resumeSession()
                result.success(null)
            }
            "stopSession" -> {
                current?.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** ARCore may answer "checking" first; retry briefly before giving up. */
    private fun checkAvailability(result: MethodChannel.Result, attempt: Int) {
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(activity)
        } catch (e: Exception) {
            return result.success("unknown")
        }
        if (availability.isTransient && attempt < 12) {
            main.postDelayed({ checkAvailability(result, attempt + 1) }, 250)
            return
        }
        result.success(
            when (availability) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED -> "supported"
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "not_installed"
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD -> "apk_too_old"
                ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
                else -> "unknown"
            },
        )
    }

    private fun requestInstall(result: MethodChannel.Result) {
        try {
            val status = ArCoreApk.getInstance().requestInstall(activity, true)
            result.success(
                if (status == ArCoreApk.InstallStatus.INSTALLED) "installed" else "requested",
            )
        } catch (e: UnavailableUserDeclinedInstallationException) {
            result.success("declined")
        } catch (e: UnavailableDeviceNotCompatibleException) {
            result.success("incompatible")
        } catch (e: Exception) {
            result.error("install", e.message, null)
        }
    }
}
