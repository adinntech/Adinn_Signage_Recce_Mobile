package com.example.signage_recce.ar

import android.opengl.GLES20
import android.opengl.Matrix
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import java.nio.FloatBuffer

/**
 * Translucent indicators for the surfaces ARCore has detected: white for
 * floors / ground, red for walls. The preferred surface type for the current
 * signage item is drawn stronger.
 */
internal class PlaneRenderer {
    private var program = 0
    private var aPosition = 0
    private var uMvp = 0
    private var uColor = 0
    private var buffer: FloatBuffer = GlUtil.floatBuffer(3 * 64)

    private val model = FloatArray(16)
    private val modelView = FloatArray(16)
    private val mvp = FloatArray(16)

    fun create() {
        program = GlUtil.program(VERTEX, FRAGMENT)
        aPosition = GLES20.glGetAttribLocation(program, "a_Position")
        uMvp = GLES20.glGetUniformLocation(program, "u_Mvp")
        uColor = GLES20.glGetUniformLocation(program, "u_Color")
        GlUtil.checkError("PlaneRenderer.create")
    }

    fun draw(planes: Collection<Plane>, view: FloatArray, projection: FloatArray, preferVertical: Boolean) {
        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        // Keep destination alpha at 1 so captures stay opaque.
        GLES20.glBlendFuncSeparate(
            GLES20.GL_SRC_ALPHA,
            GLES20.GL_ONE_MINUS_SRC_ALPHA,
            GLES20.GL_ZERO,
            GLES20.GL_ONE,
        )
        GLES20.glDepthMask(false)
        GLES20.glEnableVertexAttribArray(aPosition)
        for (plane in planes) {
            if (plane.trackingState != TrackingState.TRACKING || plane.subsumedBy != null) continue
            if (plane.type == Plane.Type.HORIZONTAL_DOWNWARD_FACING) continue
            val polygon = plane.polygon ?: continue
            val points = polygon.remaining() / 2
            if (points < 3) continue
            // Triangle fan: centre, every polygon vertex, first vertex again.
            val needed = (points + 2) * 3
            if (buffer.capacity() < needed) buffer = GlUtil.floatBuffer(needed * 2)
            buffer.clear()
            buffer.put(0f).put(0f).put(0f)
            polygon.rewind()
            val firstX = polygon.get(0)
            val firstZ = polygon.get(1)
            for (i in 0 until points) {
                buffer.put(polygon.get(i * 2)).put(0f).put(polygon.get(i * 2 + 1))
            }
            buffer.put(firstX).put(0f).put(firstZ)
            buffer.position(0)

            plane.centerPose.toMatrix(model, 0)
            Matrix.multiplyMM(modelView, 0, view, 0, model, 0)
            Matrix.multiplyMM(mvp, 0, projection, 0, modelView, 0)
            GLES20.glUniformMatrix4fv(uMvp, 1, false, mvp, 0)
            GLES20.glVertexAttribPointer(aPosition, 3, GLES20.GL_FLOAT, false, 0, buffer)

            val vertical = plane.type == Plane.Type.VERTICAL
            val preferred = vertical == preferVertical
            val fill = if (preferred) 0.30f else 0.14f
            if (vertical) {
                GLES20.glUniform4f(uColor, 0.84f, 0.10f, 0.13f, fill)
            } else {
                GLES20.glUniform4f(uColor, 1f, 1f, 1f, fill)
            }
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_FAN, 0, points + 2)
            // Outline.
            if (vertical) {
                GLES20.glUniform4f(uColor, 0.84f, 0.10f, 0.13f, 0.85f)
            } else {
                GLES20.glUniform4f(uColor, 1f, 1f, 1f, 0.85f)
            }
            GLES20.glLineWidth(3f)
            GLES20.glDrawArrays(GLES20.GL_LINE_LOOP, 1, points)
        }
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDepthMask(true)
        GLES20.glDisable(GLES20.GL_BLEND)
        GlUtil.checkError("PlaneRenderer.draw")
    }

    private companion object {
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
