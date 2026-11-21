package com.example.signage_recce.ar

import android.graphics.Bitmap
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.util.Log
import com.google.ar.core.Anchor
import com.google.ar.core.Camera
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.InstantPlacementPoint
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.SessionPausedException
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Callbacks from the GL thread (the view posts them to the main thread). */
internal interface ArRendererListener {
    fun onTracking(state: String, reason: String)
    fun onPlanes(horizontal: Int, vertical: Int)
    fun onAnchorLost()
    fun onRendererError(code: String, message: String)
    fun displayRotation(): Int

    /** A scene object's anchor stopped tracking for good. */
    fun onObjectLost(id: String)

    /** Placement indicator found (or lost) a surface at the screen centre. */
    fun onReticle(hit: Boolean, surface: String?)
}

/** Shared model of one signage item: data + lazily built GPU mesh. */
internal class SceneModel(val data: ModelData) {
    var mesh: ModelMesh? = null
}

/** One placement in the multi-object scene (AR Placement ID = [id]). */
internal class SceneObject(val id: String) {
    var modelKey: String = ""
    var anchor: Anchor? = null

    /** "vertical", "horizontal" or "manual" – which pivot the anchor uses. */
    var surface = "horizontal"
    var visible = true
    var x = 0f
    var y = 0f
    var z = 0f
    var yaw = 0f
    var roll = 0f
    var scale = 1f
    val matrix = FloatArray(16)
    var matrixValid = false
}

/**
 * ARCore frame loop on the GLSurfaceView thread: camera background, plane
 * indicators, the anchored signage models, hit-test placement, object
 * selection and scene capture (glReadPixels of the rendered camera + model
 * frame).
 *
 * Two APIs share this renderer:
 * * the original single-model API (setModel / queueTap / userYaw …), kept
 *   unchanged for compatibility;
 * * the multi-object scene API (registerModel / queuePlaceObject / …):
 *   every placement has its own anchor and transform while placements of
 *   the same signage item share one GPU mesh.
 */
internal class ArRenderer(private val listener: ArRendererListener) : GLSurfaceView.Renderer {
    private class TapRequest(val x: Float, val y: Float, val manual: Boolean, val callback: (Map<String, Any?>) -> Unit)

    private sealed class SceneRequest {
        class Place(
            val id: String,
            val key: String,
            val x: Float,
            val y: Float,
            val manual: Boolean,
            val callback: (Map<String, Any?>) -> Unit,
        ) : SceneRequest()

        class AnchorAt(
            val id: String,
            val key: String,
            val pose: FloatArray,
            val surface: String,
            val callback: (Map<String, Any?>) -> Unit,
        ) : SceneRequest()

        class HitTest(val x: Float, val y: Float, val callback: (String?) -> Unit) : SceneRequest()
    }

    private class PoseChoice(val pose: Pose?, val surface: String, val reason: String?)

    @Volatile var session: Session? = null

    @Volatile var resumed = false

    @Volatile var planesVisible = true

    // User transform relative to the anchor (single-model API).
    @Volatile var userYaw = 0f
    @Volatile var userScale = 1f
    @Volatile var offsetX = 0f
    @Volatile var offsetY = 0f
    @Volatile var offsetZ = 0f

    @Volatile private var pendingModel: ModelData? = null
    @Volatile private var removeRequested = false
    private var model: ModelData? = null
    private val taps = ConcurrentLinkedQueue<TapRequest>()
    @Volatile private var captureCallback: ((ByteArray?, String?) -> Unit)? = null

    // Multi-object scene (GL thread only, changed through [commands]).
    private val sceneModels = HashMap<String, SceneModel>()
    private val objects = LinkedHashMap<String, SceneObject>()
    private val commands = ConcurrentLinkedQueue<() -> Unit>()
    private val requests = ConcurrentLinkedQueue<SceneRequest>()
    @Volatile private var selectedId: String? = null
    @Volatile private var indicatorActive = false
    @Volatile private var indicatorVertical = false
    private var lastReticleHit = false
    private var lastReticleSurface: String? = null

    private val background = BackgroundRenderer()
    private val planes = PlaneRenderer()
    private val modelRenderer = ModelRenderer()
    private val overlay = OverlayRenderer()
    private var glReady = false
    private var textureBound = false

    private var width = 1
    private var height = 1
    @Volatile private var viewportChanged = false

    private var anchor: Anchor? = null
    /** "vertical", "horizontal" or "manual" – which pivot the anchor uses. */
    private var anchorSurface = "horizontal"

    private var lastTracking = ""
    private var lastReason = ""
    private var lastH = -1
    private var lastV = -1

    private val view = FloatArray(16)
    private val projection = FloatArray(16)
    private val modelMatrix = FloatArray(16)
    private val reticleMatrix = FloatArray(16)
    private var haveMatrices = false

    private val encoder = Executors.newSingleThreadExecutor()

    // --- Single-model API ---------------------------------------------------

    fun setModel(data: ModelData) {
        pendingModel = data
    }

    fun queueTap(x: Float, y: Float, manual: Boolean, callback: (Map<String, Any?>) -> Unit) {
        taps.add(TapRequest(x, y, manual, callback))
    }

    fun requestRemove() {
        removeRequested = true
    }

    // --- Multi-object scene API (any thread) --------------------------------

    /** Adds / replaces the shared model of a signage item. */
    fun registerModel(key: String, data: ModelData) {
        commands.add {
            sceneModels[key]?.mesh?.let { modelRenderer.releaseMesh(it) }
            sceneModels[key] = SceneModel(data)
        }
    }

    fun queuePlaceObject(id: String, key: String, x: Float, y: Float, manual: Boolean, callback: (Map<String, Any?>) -> Unit) {
        requests.add(SceneRequest.Place(id, key, x, y, manual, callback))
    }

    fun queueAnchorObject(id: String, key: String, pose: FloatArray, surface: String, callback: (Map<String, Any?>) -> Unit) {
        requests.add(SceneRequest.AnchorAt(id, key, pose, surface, callback))
    }

    fun queueHitTest(x: Float, y: Float, callback: (String?) -> Unit) {
        requests.add(SceneRequest.HitTest(x, y, callback))
    }

    fun setObjectTransform(id: String, x: Float, y: Float, z: Float, yaw: Float, roll: Float, scale: Float) {
        commands.add {
            val o = objects[id] ?: return@add
            o.x = x
            o.y = y
            o.z = z
            o.yaw = yaw
            o.roll = roll
            o.scale = scale.coerceIn(0.05f, 20f)
        }
    }

    fun setObjectVisible(id: String, visible: Boolean) {
        commands.add { objects[id]?.visible = visible }
    }

    fun removeObject(id: String) {
        commands.add {
            objects.remove(id)?.anchor?.detach()
            if (selectedId == id) selectedId = null
        }
    }

    fun selectObject(id: String?) {
        selectedId = id
    }

    fun setPlacementIndicator(active: Boolean, vertical: Boolean) {
        indicatorVertical = vertical
        indicatorActive = active
    }

    fun requestCapture(callback: (ByteArray?, String?) -> Unit) {
        val previous = captureCallback
        captureCallback = callback
        previous?.invoke(null, "Superseded by a newer capture")
    }

    /** Fails pending requests (session closing). Any thread. */
    fun cancelPending(reason: String) {
        captureCallback?.invoke(null, reason)
        captureCallback = null
        while (true) {
            val t = taps.poll() ?: break
            t.callback(mapOf("placed" to false, "reason" to reason))
        }
        while (true) {
            when (val r = requests.poll() ?: break) {
                is SceneRequest.Place -> r.callback(mapOf("placed" to false, "reason" to reason))
                is SceneRequest.AnchorAt -> r.callback(mapOf("placed" to false, "reason" to reason))
                is SceneRequest.HitTest -> r.callback(null)
            }
        }
    }

    fun shutdown() {
        encoder.shutdown()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        try {
            background.create()
            planes.create()
            modelRenderer.create()
            overlay.create()
            glReady = true
            textureBound = false
            // A recreated context lost the old buffers: rebuild the models.
            model?.let { pendingModel = pendingModel ?: it }
            for (m in sceneModels.values) m.mesh = null
        } catch (e: Exception) {
            Log.e(TAG, "GL init failed", e)
            listener.onRendererError("render_init", e.message ?: "OpenGL initialisation failed")
        }
    }

    override fun onSurfaceChanged(gl: GL10?, w: Int, h: Int) {
        GLES20.glViewport(0, 0, w, h)
        width = w.coerceAtLeast(1)
        height = h.coerceAtLeast(1)
        viewportChanged = true
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        if (!glReady || !resumed) return
        if (!textureBound) {
            s.setCameraTextureName(background.textureId)
            textureBound = true
        }
        if (viewportChanged) {
            s.setDisplayGeometry(listener.displayRotation(), width, height)
            viewportChanged = false
        }
        pendingModel?.let { data ->
            pendingModel = null
            try {
                modelRenderer.setModel(data)
                model = data
            } catch (e: Exception) {
                Log.e(TAG, "Model build failed", e)
                listener.onRendererError("model", e.message ?: "Could not build the signage model")
            }
        }
        if (removeRequested) {
            removeRequested = false
            anchor?.detach()
            anchor = null
        }
        while (true) {
            val command = commands.poll() ?: break
            try {
                command()
            } catch (e: Exception) {
                Log.w(TAG, "Scene command failed", e)
            }
        }

        val frame: Frame = try {
            s.update()
        } catch (e: CameraNotAvailableException) {
            reportTracking("stopped", "CAMERA_UNAVAILABLE")
            failCapture("Camera not available")
            return
        } catch (e: SessionPausedException) {
            return
        } catch (e: Exception) {
            Log.e(TAG, "Session update failed", e)
            failCapture(e.message ?: "AR update failed")
            return
        }

        background.draw(frame)
        val camera = frame.camera
        reportTracking(camera.trackingState.name.lowercase(), camera.trackingFailureReason.name)

        val tracking = camera.trackingState == TrackingState.TRACKING
        if (tracking) {
            camera.getProjectionMatrix(projection, 0, 0.05f, 100f)
            camera.getViewMatrix(view, 0)
            haveMatrices = true
        }
        processTaps(frame, camera, tracking)
        processSceneRequests(frame, camera, tracking)
        if (!tracking) {
            reportReticle(false, null)
            failCapture("Tracking lost – move the phone slowly and try again")
            return
        }

        val allPlanes = s.getAllTrackables(Plane::class.java)
        reportPlanes(allPlanes)

        val capturing = captureCallback != null
        // Plane indicators are UI hints: never part of a capture.
        if (planesVisible && !capturing) {
            val preferVertical = if (indicatorActive) indicatorVertical else model?.preferVertical ?: false
            planes.draw(allPlanes, view, projection, preferVertical)
        }

        var modelDrawn = false
        val a = anchor
        if (a != null) {
            when (a.trackingState) {
                TrackingState.TRACKING -> {
                    computeModelMatrix(a)
                    modelRenderer.draw(modelMatrix, view, projection)
                    modelDrawn = modelRenderer.hasModel
                }
                TrackingState.STOPPED -> {
                    anchor = null
                    listener.onAnchorLost()
                }
                else -> Unit // Paused: keep the anchor, skip drawing this frame.
            }
        }
        if (drawSceneObjects()) modelDrawn = true

        if (!capturing) {
            drawSelection()
            drawReticle(frame)
        }

        if (capturing) {
            if (!modelDrawn) {
                failCapture("Place the signage model before capturing")
            } else {
                readFrame()
            }
        }
    }

    // --- Single-model drawing ----------------------------------------------

    private fun computeModelMatrix(a: Anchor) {
        val m = model ?: return
        a.pose.toMatrix(modelMatrix, 0)
        Matrix.rotateM(modelMatrix, 0, Math.toDegrees(userYaw.toDouble()).toFloat(), 0f, 1f, 0f)
        Matrix.translateM(modelMatrix, 0, offsetX, offsetY, offsetZ)
        Matrix.scaleM(modelMatrix, 0, userScale, userScale, userScale)
        val pivot = if (anchorSurface == "horizontal") m.pivotGround else m.pivotWall
        Matrix.translateM(modelMatrix, 0, -pivot[0], -pivot[1], -pivot[2])
    }

    // --- Scene drawing ------------------------------------------------------

    private fun meshFor(m: SceneModel): ModelMesh? {
        m.mesh?.let { return it }
        return try {
            modelRenderer.buildMesh(m.data).also { m.mesh = it }
        } catch (e: Exception) {
            Log.e(TAG, "Model build failed", e)
            null
        }
    }

    /**
     * Anchor frame → offset (x along the surface, y up, z out of the
     * surface / toward the camera) → yaw (vertical axis) → roll (surface
     * normal) → preview scale → model pivot.
     */
    private fun computeObjectMatrix(o: SceneObject, data: ModelData, a: Anchor) {
        val m = o.matrix
        a.pose.toMatrix(m, 0)
        Matrix.translateM(m, 0, o.x, o.y, o.z)
        Matrix.rotateM(m, 0, Math.toDegrees(o.yaw.toDouble()).toFloat(), 0f, 1f, 0f)
        Matrix.rotateM(m, 0, Math.toDegrees(o.roll.toDouble()).toFloat(), 0f, 0f, 1f)
        Matrix.scaleM(m, 0, o.scale, o.scale, o.scale)
        val pivot = if (o.surface == "horizontal") data.pivotGround else data.pivotWall
        Matrix.translateM(m, 0, -pivot[0], -pivot[1], -pivot[2])
        o.matrixValid = true
    }

    /** Draws every visible tracked placement; true when one was drawn. */
    private fun drawSceneObjects(): Boolean {
        var drawn = false
        var lost: MutableList<SceneObject>? = null
        for (o in objects.values) {
            val a = o.anchor
            if (a == null) {
                o.matrixValid = false
                continue
            }
            when (a.trackingState) {
                TrackingState.TRACKING -> {
                    val m = sceneModels[o.modelKey] ?: continue
                    val mesh = meshFor(m) ?: continue
                    computeObjectMatrix(o, m.data, a)
                    if (o.visible && !mesh.isEmpty) {
                        modelRenderer.drawMesh(mesh, o.matrix, view, projection)
                        drawn = true
                    }
                }
                TrackingState.STOPPED -> (lost ?: mutableListOf<SceneObject>().also { lost = it }).add(o)
                else -> o.matrixValid = false // Paused: keep the anchor.
            }
        }
        lost?.forEach { o ->
            o.anchor = null
            o.matrixValid = false
            listener.onObjectLost(o.id)
        }
        return drawn
    }

    private fun drawSelection() {
        val o = selectedId?.let { objects[it] } ?: return
        if (!o.visible || !o.matrixValid) return
        val data = sceneModels[o.modelKey]?.data ?: return
        overlay.drawBox(data.boundsMin, data.boundsMax, o.matrix, view, projection)
    }

    private fun drawReticle(frame: Frame) {
        if (!indicatorActive) {
            reportReticle(false, null)
            return
        }
        val choice = choosePlaneHit(frame, width / 2f, height / 2f, indicatorVertical)
        if (choice == null) {
            reportReticle(false, null)
            return
        }
        val (hit, plane) = choice
        hit.hitPose.toMatrix(reticleMatrix, 0)
        val vertical = plane.type == Plane.Type.VERTICAL
        overlay.drawReticle(reticleMatrix, view, projection, vertical == indicatorVertical)
        reportReticle(true, if (vertical) "vertical" else "horizontal")
    }

    private fun reportReticle(hit: Boolean, surface: String?) {
        if (hit == lastReticleHit && surface == lastReticleSurface) return
        lastReticleHit = hit
        lastReticleSurface = surface
        listener.onReticle(hit, surface)
    }

    // --- Placement ----------------------------------------------------------

    private fun processTaps(frame: Frame, camera: Camera, tracking: Boolean) {
        while (true) {
            val tap = taps.poll() ?: break
            if (!tracking) {
                tap.callback(mapOf("placed" to false, "reason" to "not_tracking"))
                continue
            }
            tap.callback(place(frame, camera, tap))
        }
    }

    private fun processSceneRequests(frame: Frame, camera: Camera, tracking: Boolean) {
        while (true) {
            when (val r = requests.poll() ?: break) {
                is SceneRequest.Place -> r.callback(
                    if (tracking) placeObject(frame, camera, r)
                    else mapOf("placed" to false, "reason" to "not_tracking"),
                )
                is SceneRequest.AnchorAt -> r.callback(
                    if (tracking) anchorObject(r)
                    else mapOf("placed" to false, "reason" to "not_tracking"),
                )
                is SceneRequest.HitTest -> r.callback(hitTestObjects(r.x, r.y))
            }
        }
    }

    /** First tracked plane hit at a pixel, preferring [preferVertical] planes. */
    private fun choosePlaneHit(frame: Frame, px: Float, py: Float, preferVertical: Boolean): Pair<HitResult, Plane>? {
        val hits = try {
            frame.hitTest(px, py)
        } catch (e: Exception) {
            emptyList<HitResult>()
        }
        var fallback: Pair<HitResult, Plane>? = null
        for (hit in hits) {
            val plane = hit.trackable as? Plane ?: continue
            if (plane.trackingState != TrackingState.TRACKING) continue
            if (!plane.isPoseInPolygon(hit.hitPose)) continue
            if (plane.type == Plane.Type.HORIZONTAL_DOWNWARD_FACING) continue
            val vertical = plane.type == Plane.Type.VERTICAL
            if (vertical == preferVertical) return hit to plane
            if (fallback == null) fallback = hit to plane
        }
        return fallback
    }

    /** Anchor pose for a tap (detected surface, or instant placement). */
    private fun findPose(frame: Frame, camera: Camera, px: Float, py: Float, preferVertical: Boolean, manual: Boolean): PoseChoice {
        val chosen = choosePlaneHit(frame, px, py, preferVertical)
        if (chosen != null) {
            val (hit, plane) = chosen
            val hitPose = hit.hitPose
            return if (plane.type == Plane.Type.VERTICAL) {
                // Board faces out of the wall: model +Z along the wall normal.
                val n = plane.centerPose.yAxis
                PoseChoice(yawPose(hitPose, atan2(n[0], n[2])), "vertical", null)
            } else {
                PoseChoice(yawPose(hitPose, facingCamera(camera, hitPose)), "horizontal", null)
            }
        }
        if (manual) {
            // No detected surface (e.g. glass): ARCore instant placement at
            // an estimated distance, facing the camera.
            val instant = try {
                frame.hitTestInstantPlacement(px, py, 2.0f)
            } catch (e: Exception) {
                emptyList<HitResult>()
            }
            val hit = instant.firstOrNull { it.trackable is InstantPlacementPoint }
                ?: return PoseChoice(null, "", "no_surface")
            return PoseChoice(yawPose(hit.hitPose, facingCamera(camera, hit.hitPose)), "manual", null)
        }
        return PoseChoice(null, "", "no_surface")
    }

    private fun place(frame: Frame, camera: Camera, tap: TapRequest): Map<String, Any?> {
        val choice = findPose(frame, camera, tap.x * width, tap.y * height, model?.preferVertical ?: false, tap.manual)
        val pose = choice.pose ?: return mapOf("placed" to false, "reason" to choice.reason)
        val s = session ?: return mapOf("placed" to false, "reason" to "no_session")
        val newAnchor = try {
            s.createAnchor(pose)
        } catch (e: Exception) {
            return mapOf("placed" to false, "reason" to "anchor_failed", "message" to e.message)
        }
        anchor?.detach()
        anchor = newAnchor
        anchorSurface = choice.surface
        return mapOf("placed" to true, "surface" to choice.surface)
    }

    private fun poseList(p: Pose): List<Double> =
        listOf(p.tx(), p.ty(), p.tz(), p.qx(), p.qy(), p.qz(), p.qw()).map { it.toDouble() }

    private fun attach(id: String, key: String, pose: Pose, surface: String): Map<String, Any?> {
        val s = session ?: return mapOf("placed" to false, "reason" to "no_session")
        val newAnchor = try {
            s.createAnchor(pose)
        } catch (e: Exception) {
            return mapOf("placed" to false, "reason" to "anchor_failed", "message" to e.message)
        }
        val o = objects.getOrPut(id) { SceneObject(id) }
        // Re-anchoring an object releases its previous anchor (no duplicates).
        o.anchor?.detach()
        o.anchor = newAnchor
        o.modelKey = key
        o.surface = surface
        o.matrixValid = false
        return mapOf("placed" to true, "surface" to surface, "pose" to poseList(newAnchor.pose))
    }

    private fun placeObject(frame: Frame, camera: Camera, r: SceneRequest.Place): Map<String, Any?> {
        val m = sceneModels[r.key] ?: return mapOf("placed" to false, "reason" to "no_model")
        val choice = findPose(frame, camera, r.x * width, r.y * height, m.data.preferVertical, r.manual)
        val pose = choice.pose ?: return mapOf("placed" to false, "reason" to choice.reason)
        return attach(r.id, r.key, pose, choice.surface)
    }

    private fun anchorObject(r: SceneRequest.AnchorAt): Map<String, Any?> {
        if (!sceneModels.containsKey(r.key)) return mapOf("placed" to false, "reason" to "no_model")
        if (r.pose.size != 7) return mapOf("placed" to false, "reason" to "bad_pose")
        val pose = Pose(
            floatArrayOf(r.pose[0], r.pose[1], r.pose[2]),
            floatArrayOf(r.pose[3], r.pose[4], r.pose[5], r.pose[6]),
        )
        return attach(r.id, r.key, pose, r.surface)
    }

    /**
     * Placement id of the nearest visible object under a normalised screen
     * point: the screen ray is intersected with each object's model bounds
     * in model space.
     */
    private fun hitTestObjects(nx: Float, ny: Float): String? {
        if (!haveMatrices) return null
        val vp = FloatArray(16)
        val inv = FloatArray(16)
        Matrix.multiplyMM(vp, 0, projection, 0, view, 0)
        if (!Matrix.invertM(inv, 0, vp, 0)) return null
        val ndcX = nx * 2f - 1f
        val ndcY = 1f - ny * 2f
        val near = unproject(inv, ndcX, ndcY, -1f) ?: return null
        val far = unproject(inv, ndcX, ndcY, 1f) ?: return null
        var bestId: String? = null
        var bestT = Float.MAX_VALUE
        val invModel = FloatArray(16)
        for (o in objects.values) {
            if (!o.visible || !o.matrixValid || o.anchor == null) continue
            val data = sceneModels[o.modelKey]?.data ?: continue
            if (!Matrix.invertM(invModel, 0, o.matrix, 0)) continue
            val ln = transformPoint(invModel, near)
            val lf = transformPoint(invModel, far)
            val dir = floatArrayOf(lf[0] - ln[0], lf[1] - ln[1], lf[2] - ln[2])
            // Thin boards: pad the box so a tap on the face still hits.
            val pad = 0.05f / max(o.scale, 0.05f)
            val t = rayBox(ln, dir, data.boundsMin, data.boundsMax, pad) ?: continue
            if (t < bestT) {
                bestT = t
                bestId = o.id
            }
        }
        return bestId
    }

    private fun unproject(inv: FloatArray, x: Float, y: Float, z: Float): FloatArray? {
        val out = FloatArray(4)
        Matrix.multiplyMV(out, 0, inv, 0, floatArrayOf(x, y, z, 1f), 0)
        if (out[3] == 0f) return null
        return floatArrayOf(out[0] / out[3], out[1] / out[3], out[2] / out[3])
    }

    private fun transformPoint(m: FloatArray, p: FloatArray): FloatArray {
        val out = FloatArray(4)
        Matrix.multiplyMV(out, 0, m, 0, floatArrayOf(p[0], p[1], p[2], 1f), 0)
        val w = if (out[3] == 0f) 1f else out[3]
        return floatArrayOf(out[0] / w, out[1] / w, out[2] / w)
    }

    /** Slab test; returns the entry parameter (0..1 along the ray) or null. */
    private fun rayBox(o: FloatArray, d: FloatArray, bMin: FloatArray, bMax: FloatArray, pad: Float): Float? {
        var tMin = 0f
        var tMax = 1f
        for (k in 0..2) {
            val lo = bMin[k] - pad
            val hi = bMax[k] + pad
            if (kotlin.math.abs(d[k]) < 1e-9f) {
                if (o[k] < lo || o[k] > hi) return null
                continue
            }
            var t1 = (lo - o[k]) / d[k]
            var t2 = (hi - o[k]) / d[k]
            if (t1 > t2) {
                val tmp = t1
                t1 = t2
                t2 = tmp
            }
            tMin = max(tMin, t1)
            tMax = min(tMax, t2)
            if (tMin > tMax) return null
        }
        return tMin
    }

    private fun facingCamera(camera: Camera, at: Pose): Float {
        val c = camera.pose
        return atan2(c.tx() - at.tx(), c.tz() - at.tz())
    }

    private fun yawPose(at: Pose, yaw: Float): Pose =
        Pose(
            floatArrayOf(at.tx(), at.ty(), at.tz()),
            floatArrayOf(0f, sin(yaw / 2f), 0f, cos(yaw / 2f)),
        )

    private fun reportTracking(state: String, reason: String) {
        if (state == lastTracking && reason == lastReason) return
        lastTracking = state
        lastReason = reason
        listener.onTracking(state, reason)
    }

    private fun reportPlanes(all: Collection<Plane>) {
        var h = 0
        var v = 0
        for (p in all) {
            if (p.trackingState != TrackingState.TRACKING || p.subsumedBy != null) continue
            when (p.type) {
                Plane.Type.VERTICAL -> v++
                Plane.Type.HORIZONTAL_UPWARD_FACING -> h++
                else -> Unit
            }
        }
        if (h == lastH && v == lastV) return
        lastH = h
        lastV = v
        listener.onPlanes(h, v)
    }

    private fun failCapture(reason: String) {
        val cb = captureCallback ?: return
        captureCallback = null
        cb(null, reason)
    }

    /** Reads the frame just rendered (camera + models) and encodes a PNG. */
    private fun readFrame() {
        val cb = captureCallback ?: return
        captureCallback = null
        val w = width
        val h = height
        val pixels = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        GLES20.glReadPixels(0, 0, w, h, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
        GlUtil.checkError("glReadPixels")
        encoder.execute {
            try {
                // Force opaque pixels (RGBA byte order matches ARGB_8888 memory).
                for (i in 3 until w * h * 4 step 4) pixels.put(i, 0xFF.toByte())
                pixels.rewind()
                val raw = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                raw.copyPixelsFromBuffer(pixels)
                // OpenGL rows start at the bottom: flip to image orientation.
                val flip = android.graphics.Matrix().apply { preScale(1f, -1f) }
                val image = Bitmap.createBitmap(raw, 0, 0, w, h, flip, false)
                raw.recycle()
                val out = ByteArrayOutputStream()
                image.compress(Bitmap.CompressFormat.PNG, 100, out)
                image.recycle()
                cb(out.toByteArray(), null)
            } catch (e: Throwable) {
                Log.e(TAG, "Capture encode failed", e)
                cb(null, e.message ?: "Could not encode the AR capture")
            }
        }
    }

    private companion object {
        const val TAG = "AdinnAr"
    }
}
