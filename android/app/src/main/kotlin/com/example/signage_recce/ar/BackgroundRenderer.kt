package com.example.signage_recce.ar

import android.opengl.GLES11Ext
import android.opengl.GLES20
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame

/**
 * Draws the ARCore camera image (external OES texture) as a full-screen
 * quad behind everything else. Must be used on the GL thread.
 */
internal class BackgroundRenderer {
    var textureId = -1
        private set

    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uTexture = 0
    private var uNight = 0

    // Triangle strip covering the viewport in normalised device coordinates.
    private val ndcQuad = GlUtil.floatBuffer(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val texQuad = GlUtil.floatBuffer(8)

    fun create() {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        textureId = textures[0]
        val target = GLES11Ext.GL_TEXTURE_EXTERNAL_OES
        GLES20.glBindTexture(target, textureId)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(target, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        program = GlUtil.program(VERTEX, FRAGMENT)
        aPosition = GLES20.glGetAttribLocation(program, "a_Position")
        aTexCoord = GLES20.glGetAttribLocation(program, "a_TexCoord")
        uTexture = GLES20.glGetUniformLocation(program, "u_Texture")
        uNight = GLES20.glGetUniformLocation(program, "u_Night")
        GlUtil.checkError("BackgroundRenderer.create")
    }

    /**
     * [night] 0..1 blends in the illustrative soft-blue evening grade (same
     * colour matrix as the Flutter Live Preview night view).
     */
    fun draw(frame: Frame, night: Float = 0f) {
        if (frame.hasDisplayGeometryChanged()) {
            ndcQuad.position(0)
            texQuad.position(0)
            frame.transformCoordinates2d(
                Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                ndcQuad,
                Coordinates2d.TEXTURE_NORMALIZED,
                texQuad,
            )
        }
        // No camera image yet.
        if (frame.timestamp == 0L) return

        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthMask(false)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUseProgram(program)
        GLES20.glUniform1i(uTexture, 0)
        GLES20.glUniform1f(uNight, night)
        ndcQuad.position(0)
        texQuad.position(0)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 0, ndcQuad)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 0, texQuad)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(aPosition)
        GLES20.glDisableVertexAttribArray(aTexCoord)
        GLES20.glDepthMask(true)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GlUtil.checkError("BackgroundRenderer.draw")
    }

    private companion object {
        const val VERTEX = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = a_Position;
                v_TexCoord = a_TexCoord;
            }
        """

        const val FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            uniform float u_Night;
            void main() {
                vec3 c = texture2D(u_Texture, v_TexCoord).rgb;
                vec3 n = vec3(
                    dot(c, vec3(0.36, 0.07, 0.03)) + 0.024,
                    dot(c, vec3(0.06, 0.46, 0.06)) + 0.039,
                    dot(c, vec3(0.07, 0.14, 0.68)) + 0.118);
                gl_FragColor = vec4(mix(c, clamp(n, 0.0, 1.0), u_Night), 1.0);
            }
        """
    }
}
