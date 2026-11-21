package com.example.signage_recce.ar

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** One flat convex polygon of the signage model, in metres. */
internal class ModelFace(
    val points: FloatArray,
    val normal: FloatArray,
    val color: Int,
    val label: String?,
    val labelColor: Int,
    val emissive: Boolean,
    val layer: Int,
)

/**
 * Signage model sent from Dart (same geometry as the photo Live Preview,
 * converted to metres). Pivots are the model points that sit on the anchor:
 * [pivotWall] for wall / vertical placement (back of the board, centre
 * height) and [pivotGround] for floor / ground placement.
 */
internal class ModelData(
    val faces: List<ModelFace>,
    val pivotWall: FloatArray,
    val pivotGround: FloatArray,
    val preferVertical: Boolean,
) {
    /** Axis-aligned bounds in model space (metres): selection box + hit test. */
    val boundsMin = FloatArray(3) { Float.MAX_VALUE }
    val boundsMax = FloatArray(3) { -Float.MAX_VALUE }

    init {
        for (face in faces) {
            var i = 0
            while (i + 2 < face.points.size) {
                for (k in 0..2) {
                    val v = face.points[i + k]
                    if (v < boundsMin[k]) boundsMin[k] = v
                    if (v > boundsMax[k]) boundsMax[k] = v
                }
                i += 3
            }
        }
        for (k in 0..2) {
            if (boundsMin[k] > boundsMax[k]) {
                boundsMin[k] = 0f
                boundsMax[k] = 0f
            }
        }
    }

    companion object {
        private fun floats(v: Any?): FloatArray =
            (v as? List<*>)?.map { (it as Number).toFloat() }?.toFloatArray() ?: FloatArray(0)

        private fun int(v: Any?, fallback: Int): Int = (v as? Number)?.toLong()?.toInt() ?: fallback

        /** Parses the map produced by `ArModelData.toMap()` in Dart. */
        fun fromMap(map: Map<*, *>): ModelData {
            val faces = (map["faces"] as? List<*>).orEmpty().mapNotNull { raw ->
                val f = raw as? Map<*, *> ?: return@mapNotNull null
                val points = floats(f["p"])
                if (points.size < 9 || points.size % 3 != 0) return@mapNotNull null
                val n = floats(f["n"]).let { if (it.size == 3) it else floatArrayOf(0f, 0f, 1f) }
                ModelFace(
                    points = points,
                    normal = n,
                    color = int(f["c"], Color.LTGRAY),
                    label = (f["l"] as? String)?.takeIf { it.isNotBlank() },
                    labelColor = int(f["lc"], Color.WHITE),
                    emissive = f["e"] == true,
                    layer = int(f["k"], 0),
                )
            }
            require(faces.isNotEmpty()) { "Signage model has no faces" }
            val wall = floats(map["pivotWall"]).let { if (it.size == 3) it else FloatArray(3) }
            val ground = floats(map["pivotGround"]).let { if (it.size == 3) it else FloatArray(3) }
            return ModelData(faces, wall, ground, map["preferVertical"] == true)
        }
    }
}

internal class DrawItem(val buffer: FloatBuffer, val vertexCount: Int, val textureId: Int, val layer: Int)

/**
 * GPU-ready geometry of one [ModelData]. Built once per signage item and
 * shared by every placement / preview duplicate of that item, so transform
 * changes (slider, pinch) never rebuild geometry.
 */
internal class ModelMesh(val data: ModelData, val items: List<DrawItem>) {
    val isEmpty: Boolean get() = items.isEmpty()
}

/** Renders [ModelData] with flat Lambert shading and text textures. */
internal class ModelRenderer {
    private var program = 0
    private var aPosition = 0
    private var aNormal = 0
    private var aColor = 0
    private var aUv = 0
    private var aEmissive = 0
    private var uMvp = 0
    private var uModel = 0
    private var uLight = 0
    private var uUseTexture = 0
    private var uTexture = 0
    private var uNight = 0

    /**
     * Illustrative night view (0 = day, 1 = night): unlit faces take the
     * evening grade, emissive (lit GSB) faces stay bright. Render-only –
     * geometry and quantities never change. GL thread only.
     */
    var night = 0f

    /** Model of the original single-model API (creation param / setModel). */
    private var defaultMesh: ModelMesh? = null
    private val modelView = FloatArray(16)
    private val mvp = FloatArray(16)

    val hasModel: Boolean get() = defaultMesh?.isEmpty == false

    fun create() {
        program = GlUtil.program(VERTEX, FRAGMENT)
        aPosition = GLES20.glGetAttribLocation(program, "a_Position")
        aNormal = GLES20.glGetAttribLocation(program, "a_Normal")
        aColor = GLES20.glGetAttribLocation(program, "a_Color")
        aUv = GLES20.glGetAttribLocation(program, "a_Uv")
        aEmissive = GLES20.glGetAttribLocation(program, "a_Emissive")
        uMvp = GLES20.glGetUniformLocation(program, "u_Mvp")
        uModel = GLES20.glGetUniformLocation(program, "u_Model")
        uLight = GLES20.glGetUniformLocation(program, "u_Light")
        uUseTexture = GLES20.glGetUniformLocation(program, "u_UseTexture")
        uTexture = GLES20.glGetUniformLocation(program, "u_Texture")
        uNight = GLES20.glGetUniformLocation(program, "u_Night")
        GlUtil.checkError("ModelRenderer.create")
    }

    /** Rebuilds GPU buffers of the single-model API. GL thread only. */
    fun setModel(data: ModelData) {
        release()
        defaultMesh = buildMesh(data)
    }

    /** Builds GPU buffers / label textures for [data]. GL thread only. */
    fun buildMesh(data: ModelData): ModelMesh {
        val items = mutableListOf<DrawItem>()
        val plain = mutableMapOf<Int, MutableList<Float>>()
        for (face in data.faces) {
            if (face.label != null && face.points.size == 12) {
                items += texturedItem(face)
                continue
            }
            val out = plain.getOrPut(face.layer) { mutableListOf() }
            val n = face.points.size / 3
            for (i in 1 until n - 1) {
                for (idx in intArrayOf(0, i, i + 1)) {
                    appendVertex(out, face, idx, 0f, 0f)
                }
            }
        }
        for ((layer, values) in plain) {
            val buffer = GlUtil.floatBuffer(values.toFloatArray())
            items += DrawItem(buffer, values.size / STRIDE, 0, layer)
        }
        items.sortBy { it.layer }
        GlUtil.checkError("ModelRenderer.buildMesh")
        return ModelMesh(data, items)
    }

    private fun appendVertex(out: MutableList<Float>, face: ModelFace, idx: Int, u: Float, v: Float) {
        val c = face.color
        out += face.points[idx * 3]
        out += face.points[idx * 3 + 1]
        out += face.points[idx * 3 + 2]
        out += face.normal[0]
        out += face.normal[1]
        out += face.normal[2]
        out += Color.red(c) / 255f
        out += Color.green(c) / 255f
        out += Color.blue(c) / 255f
        out += Color.alpha(c) / 255f
        out += u
        out += v
        out += if (face.emissive) 1f else 0f
    }

    /** Quad (TL, TR, BR, BL) with the label painted into a texture. */
    private fun texturedItem(face: ModelFace): DrawItem {
        val p = face.points
        fun dist(a: Int, b: Int): Float {
            val dx = p[a * 3] - p[b * 3]
            val dy = p[a * 3 + 1] - p[b * 3 + 1]
            val dz = p[a * 3 + 2] - p[b * 3 + 2]
            return sqrt(dx * dx + dy * dy + dz * dz)
        }
        val w = max(dist(0, 1), 0.01f)
        val h = max(dist(0, 3), 0.01f)
        val texW = 1024
        val texH = (texW * h / w).roundToInt().coerceIn(96, 1024)
        val bitmap = Bitmap.createBitmap(texW, texH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(face.color or (0xFF shl 24))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = face.labelColor
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }
        val label = face.label ?: ""
        paint.textSize = texH * 0.6f
        val measured = paint.measureText(label)
        if (measured > texW * 0.86f && measured > 0f) {
            paint.textSize = paint.textSize * texW * 0.86f / measured
        }
        val metrics = paint.fontMetrics
        val baseline = texH / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(label, texW / 2f, baseline, paint)

        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0])
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        bitmap.recycle()

        val values = mutableListOf<Float>()
        val uv = floatArrayOf(0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f)
        for (idx in intArrayOf(0, 1, 2, 0, 2, 3)) {
            appendVertex(values, face, idx, uv[idx * 2], uv[idx * 2 + 1])
        }
        return DrawItem(GlUtil.floatBuffer(values.toFloatArray()), 6, ids[0], face.layer)
    }

    /** Draws the single-model API mesh. */
    fun draw(model: FloatArray, view: FloatArray, projection: FloatArray) {
        defaultMesh?.let { drawMesh(it, model, view, projection) }
    }

    /** Draws a (shared) mesh with one placement's model matrix. */
    fun drawMesh(mesh: ModelMesh, model: FloatArray, view: FloatArray, projection: FloatArray) {
        val items = mesh.items
        if (items.isEmpty()) return
        Matrix.multiplyMM(modelView, 0, view, 0, model, 0)
        Matrix.multiplyMM(mvp, 0, projection, 0, modelView, 0)
        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(uMvp, 1, false, mvp, 0)
        GLES20.glUniformMatrix4fv(uModel, 1, false, model, 0)
        GLES20.glUniform3f(uLight, LIGHT[0], LIGHT[1], LIGHT[2])
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glUniform1f(uNight, night)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_CULL_FACE)
        GLES20.glEnable(GLES20.GL_BLEND)
        // Keep destination alpha at 1 so captures stay opaque.
        GLES20.glBlendFuncSeparate(
            GLES20.GL_SRC_ALPHA,
            GLES20.GL_ONE_MINUS_SRC_ALPHA,
            GLES20.GL_ZERO,
            GLES20.GL_ONE,
        )
        for (item in items) {
            if (item.layer > 0) {
                // Decals (letters, artwork) sit on their host face.
                GLES20.glEnable(GLES20.GL_POLYGON_OFFSET_FILL)
                GLES20.glPolygonOffset(-1f, -2f * min(item.layer, 8))
            } else {
                GLES20.glDisable(GLES20.GL_POLYGON_OFFSET_FILL)
            }
            if (item.textureId != 0) {
                GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, item.textureId)
                GLES20.glUniform1f(uUseTexture, 1f)
            } else {
                GLES20.glUniform1f(uUseTexture, 0f)
            }
            bind(item.buffer)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, item.vertexCount)
        }
        GLES20.glDisable(GLES20.GL_POLYGON_OFFSET_FILL)
        GLES20.glDisable(GLES20.GL_BLEND)
        for (a in intArrayOf(aPosition, aNormal, aColor, aUv, aEmissive)) {
            if (a >= 0) GLES20.glDisableVertexAttribArray(a)
        }
        GlUtil.checkError("ModelRenderer.draw")
    }

    private fun bind(buffer: FloatBuffer) {
        val stride = STRIDE * 4
        fun attr(location: Int, size: Int, offset: Int) {
            if (location < 0) return
            buffer.position(offset)
            GLES20.glVertexAttribPointer(location, size, GLES20.GL_FLOAT, false, stride, buffer)
            GLES20.glEnableVertexAttribArray(location)
        }
        attr(aPosition, 3, 0)
        attr(aNormal, 3, 3)
        attr(aColor, 4, 6)
        attr(aUv, 2, 10)
        attr(aEmissive, 1, 12)
        buffer.position(0)
    }

    /** Releases the single-model API mesh. */
    fun release() {
        defaultMesh?.let { releaseMesh(it) }
        defaultMesh = null
    }

    /** Deletes the label textures of [mesh] (current GL context only). */
    fun releaseMesh(mesh: ModelMesh) {
        val textures = mesh.items.filter { it.textureId != 0 }.map { it.textureId }.toIntArray()
        if (textures.isNotEmpty()) GLES20.glDeleteTextures(textures.size, textures, 0)
    }

    private companion object {
        /** position(3) normal(3) colour(4) uv(2) emissive(1). */
        const val STRIDE = 13

        val LIGHT = floatArrayOf(-0.35f, 0.85f, 0.4f).let { v ->
            val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
            floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
        }

        const val VERTEX = """
            uniform mat4 u_Mvp;
            uniform mat4 u_Model;
            uniform vec3 u_Light;
            attribute vec3 a_Position;
            attribute vec3 a_Normal;
            attribute vec4 a_Color;
            attribute vec2 a_Uv;
            attribute float a_Emissive;
            varying vec4 v_Color;
            varying vec2 v_Uv;
            varying float v_Shade;
            varying float v_Emissive;
            void main() {
                vec3 n = normalize((u_Model * vec4(a_Normal, 0.0)).xyz);
                float lambert = 0.58 + 0.42 * max(dot(n, u_Light), 0.0);
                v_Shade = mix(lambert, 1.0, a_Emissive);
                v_Emissive = a_Emissive;
                v_Color = a_Color;
                v_Uv = a_Uv;
                gl_Position = u_Mvp * vec4(a_Position, 1.0);
            }
        """

        const val FRAGMENT = """
            precision mediump float;
            uniform float u_UseTexture;
            uniform sampler2D u_Texture;
            uniform float u_Night;
            varying vec4 v_Color;
            varying vec2 v_Uv;
            varying float v_Shade;
            varying float v_Emissive;
            void main() {
                vec4 base = u_UseTexture > 0.5 ? texture2D(u_Texture, v_Uv) : v_Color;
                vec3 rgb = base.rgb * v_Shade;
                vec3 lit = min(rgb * 1.12 + vec3(0.04), vec3(1.0));
                vec3 dusk = rgb * vec3(0.42, 0.50, 0.70) + vec3(0.02, 0.03, 0.07);
                vec3 nightRgb = v_Emissive > 0.5 ? lit : dusk;
                gl_FragColor = vec4(mix(rgb, nightRgb, u_Night), max(base.a, 0.35));
            }
        """
    }
}
