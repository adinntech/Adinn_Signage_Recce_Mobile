package com.example.signage_recce.ar

import android.opengl.GLES20
import android.opengl.Matrix
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin

/**
 * Editing overlays drawn on top of the camera image: the selection box of
 * the active scene object and the surface placement indicator (reticle).
 * Both are UI hints and are never drawn into an AR capture.
 */
internal class OverlayRenderer {
    private var program = 0
    private var aPosition = 0
    private var uMvp = 0
    private var uColor = 0

    private val box: FloatBuffer = GlUtil.floatBuffer(24 * 3)
    private val ring: FloatBuffer
    private val modelView = FloatArray(16)
    private val mvp = FloatArray(16)

    init {
        val values = FloatArray(RING_SEGMENTS * 3)
        for (i in 0 until RING_SEGMENTS) {
            val a = (2.0 * Math.PI * i / RING_SEGMENTS).toFloat()
            values[i * 3] = cos(a)
            values[i * 3 + 1] = 0f
            values[i * 3 + 2] = sin(a)
        }
        ring = GlUtil.floatBuffer(values)
    }

    fun create() {
        program = GlUtil.program(VERTEX, FRAGMENT)
        aPosition = GLES20.glGetAttribLocation(program, "a_Position")
        uMvp = GLES20.glGetUniformLocation(program, "u_Mvp")
        uColor = GLES20.glGetUniformLocation(program, "u_Color")
        GlUtil.checkError("OverlayRenderer.create")
    }

    private fun begin(model: FloatArray, view: FloatArray, projection: FloatArray) {
        Matrix.multiplyMM(modelView, 0, view, 0, model, 0)
        Matrix.multiplyMM(mvp, 0, projection, 0, modelView, 0)
        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(uMvp, 1, false, mvp, 0)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFuncSeparate(
            GLES20.GL_SRC_ALPHA,
            GLES20.GL_ONE_MINUS_SRC_ALPHA,
            GLES20.GL_ZERO,
            GLES20.GL_ONE,
        )
        // Always visible (drawn over the model it outlines).
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glEnableVertexAttribArray(aPosition)
    }

    private fun end(where: String) {
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_BLEND)
        GlUtil.checkError(where)
    }

    /** Wireframe box [min]..[max] (model space) with the object matrix. */
    fun drawBox(min: FloatArray, max: FloatArray, model: FloatArray, view: FloatArray, projection: FloatArray) {
        val pad = 0.02f
        val x0 = min[0] - pad
        val y0 = min[1] - pad
        val z0 = min[2] - pad
        val x1 = max[0] + pad
        val y1 = max[1] + pad
        val z1 = max[2] + pad
        val c = arrayOf(
            floatArrayOf(x0, y0, z0), floatArrayOf(x1, y0, z0),
            floatArrayOf(x1, y1, z0), floatArrayOf(x0, y1, z0),
            floatArrayOf(x0, y0, z1), floatArrayOf(x1, y0, z1),
            floatArrayOf(x1, y1, z1), floatArrayOf(x0, y1, z1),
        )
        box.clear()
        for ((a, b) in EDGES) {
            box.put(c[a]).put(c[b])
        }
        box.position(0)
        begin(model, view, projection)
        GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, 0, box)
        GLES20.glUniform4f(uColor, 0.84f, 0.10f, 0.13f, 0.95f)
        GLES20.glLineWidth(4f)
        GLES20.glDrawArrays(GLES20.GL_LINES, 0, 24)
        end("OverlayRenderer.drawBox")
    }

    /**
     * Placement ring on a hit pose (pose Y axis = surface normal, so the ring
     * lies flat on floors and walls alike).
     */
    fun drawReticle(pose: FloatArray, view: FloatArray, projection: FloatArray, ready: Boolean) {
        begin(pose, view, projection)
        GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, 0, ring)
        val scaled = FloatArray(16)
        for ((radius, alpha) in arrayOf(0.12f to 0.95f, 0.05f to 0.75f)) {
            Matrix.scaleM(scaled.also { System.arraycopy(pose, 0, it, 0, 16) }, 0, radius, radius, radius)
            Matrix.multiplyMM(modelView, 0, view, 0, scaled, 0)
            Matrix.multiplyMM(mvp, 0, projection, 0, modelView, 0)
            GLES20.glUniformMatrix4fv(uMvp, 1, false, mvp, 0)
            if (ready) {
                GLES20.glUniform4f(uColor, 1f, 1f, 1f, alpha)
            } else {
                GLES20.glUniform4f(uColor, 1f, 0.6f, 0.1f, alpha)
            }
            GLES20.glLineWidth(4f)
            GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 0, RING_SEGMENTS)
        }
        end("OverlayRenderer.drawReticle")
    }

    private companion object {
        const val RING_SEGMENTS = 48

        val EDGES = arrayOf(
            0 to 1, 1 to 2, 2 to 3, 3 to 0,
            4 to 5, 5 to 6, 6 to 7, 7 to 4,
            0 to 4, 1 to 5, 2 to 6, 3 to 7,
        )

        const val VERTEX = """
            uniform mat4 u_Mvp;
            attribute vec3 a_Position;
            void main() {
                gl_Position = u_Mvp * vec4(a_Position, 1.0);
            }
        """

        const val FRAGMENT = """
            precision mediump float;
            uniform vec4 u_Color;
            void main() {
                gl_FragColor = u_Color;
            }
        """
    }
}
