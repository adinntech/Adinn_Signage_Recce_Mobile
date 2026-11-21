package com.example.signage_recce.ar

import android.app.Activity
import android.app.Application
import android.content.Context
import android.opengl.GLSurfaceView
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.WindowManager
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableDeviceNotCompatibleException
import com.google.ar.core.exceptions.UnavailableSdkTooOldException
import io.flutter.plugin.platform.PlatformView

/**
 * Native camera AR view embedded in Flutter (hybrid composition). Owns the
 * ARCore [Session] and pauses / resumes it with the activity; closing the
 * view closes the session so the camera is never left running.
 */
internal class ArPlatformView(
    private val activity: Activity,
    params: Map<*, *>,
    private val bridge: ArBridge,
) : PlatformView, ArRendererListener, Application.ActivityLifecycleCallbacks {

    val renderer = ArRenderer(this)
    private val glView = GLSurfaceView(activity)
    private var session: Session? = null
    private var disposed = false
    private var activityResumed = true

    /**
     * Another AR view was opened on top (e.g. Camera AR from the board
     * editor reached from this AR screen): this session stays paused, with
     * its anchors, until that view closes.
     */
    private var suspended = false

    val isDisposed: Boolean get() = disposed

    fun suspend() {
        if (disposed) return
        suspended = true
        pauseSession()
    }

    fun unsuspend() {
        if (disposed || !suspended) return
        suspended = false
        resumeSession()
    }

    init {
        glView.preserveEGLContextOnPause = true
        glView.setEGLContextClientVersion(2)
        glView.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        glView.setRenderer(renderer)
        glView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        glView.setWillNotDraw(false)

        (params["model"] as? Map<*, *>)?.let { applyModel(it) }
        params["planesVisible"]?.let { renderer.planesVisible = it == true }
        activity.application.registerActivityLifecycleCallbacks(this)
        bridge.attach(this)
        createSession()
    }

    fun applyModel(map: Map<*, *>): Boolean =
        try {
            renderer.setModel(ModelData.fromMap(map))
            true
        } catch (e: Exception) {
            bridge.emitError("model", e.message ?: "Invalid signage model")
            false
        }

    private fun createSession() {
        try {
            val s = Session(activity)
            val config = Config(s)
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
            config.focusMode = Config.FocusMode.AUTO
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
            config.instantPlacementMode = Config.InstantPlacementMode.LOCAL_Y_UP
            if (!s.isSupported(config)) {
                config.instantPlacementMode = Config.InstantPlacementMode.DISABLED
            }
            s.configure(config)
            session = s
            renderer.session = s
            resumeSession()
            if (renderer.resumed) bridge.emit(mapOf("type" to "ready"))
        } catch (e: UnavailableArcoreNotInstalledException) {
            bridge.emitError("not_installed", "Google Play Services for AR is not installed")
        } catch (e: UnavailableApkTooOldException) {
            bridge.emitError("apk_too_old", "Google Play Services for AR needs an update")
        } catch (e: UnavailableSdkTooOldException) {
            bridge.emitError("sdk_too_old", "This app's AR library is too old for this device")
        } catch (e: UnavailableDeviceNotCompatibleException) {
            bridge.emitError("unsupported", "This device does not support ARCore")
        } catch (e: SecurityException) {
            bridge.emitError("permission", "Camera permission is required for AR")
        } catch (e: Exception) {
            Log.e(TAG, "AR session failed", e)
            bridge.emitError("session", e.message ?: "Could not start the AR session")
        }
    }

    fun resumeSession() {
        val s = session ?: return
        if (disposed || suspended || renderer.resumed || !activityResumed) return
        try {
            s.resume()
            glView.onResume()
            renderer.resumed = true
        } catch (e: CameraNotAvailableException) {
            bridge.emitError("camera", "Camera is in use by another app. Close it and retry.")
        } catch (e: Exception) {
            bridge.emitError("session", e.message ?: "Could not resume AR")
        }
    }

    fun pauseSession() {
        if (!renderer.resumed) return
        renderer.resumed = false
        glView.onPause()
        try {
            session?.pause()
        } catch (e: Exception) {
            Log.w(TAG, "Pause failed", e)
        }
    }

    override fun getView(): View = glView

    override fun dispose() {
        if (disposed) return
        disposed = true
        activity.application.unregisterActivityLifecycleCallbacks(this)
        renderer.cancelPending("AR session closed")
        pauseSession()
        renderer.session = null
        try {
            session?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Close failed", e)
        }
        session = null
        renderer.shutdown()
        bridge.detach(this)
    }

    // --- Activity lifecycle (background / foreground) ----------------------

    override fun onActivityResumed(a: Activity) {
        if (a !== activity) return
        activityResumed = true
        resumeSession()
    }

    override fun onActivityPaused(a: Activity) {
        if (a !== activity) return
        activityResumed = false
        pauseSession()
    }

    override fun onActivityCreated(a: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(a: Activity) = Unit
    override fun onActivityStopped(a: Activity) = Unit
    override fun onActivitySaveInstanceState(a: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(a: Activity) {
        if (a === activity) dispose()
    }

    // --- Renderer callbacks (GL thread) -----------------------------------

    override fun onTracking(state: String, reason: String) =
        bridge.emit(mapOf("type" to "tracking", "state" to state, "reason" to reason))

    override fun onPlanes(horizontal: Int, vertical: Int) =
        bridge.emit(mapOf("type" to "planes", "horizontal" to horizontal, "vertical" to vertical))

    override fun onAnchorLost() = bridge.emit(mapOf("type" to "anchorLost"))

    override fun onRendererError(code: String, message: String) = bridge.emitError(code, message)

    override fun onObjectLost(id: String) = bridge.emit(mapOf("type" to "objectLost", "id" to id))

    override fun onReticle(hit: Boolean, surface: String?) =
        bridge.emit(mapOf("type" to "reticle", "hit" to hit, "surface" to surface))

    @Suppress("DEPRECATION")
    override fun displayRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: 0
        } else {
            (activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.rotation
        }

    private companion object {
        const val TAG = "AdinnAr"
    }
}
