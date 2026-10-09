package org.nighthawklabs.retro.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

object PhotoPreparation {
    fun normalize(bytes: ByteArray): ByteArray {
        require(bytes.isNotEmpty() && bytes.size <= 64 * 1024 * 1024) { "Choose a readable photo of at most 24 megapixels." }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 24_000_000) { "Choose a readable photo of at most 24 megapixels." }
        val options = BitmapFactory.Options().apply { inSampleSize = sample(bounds.outWidth, bounds.outHeight, 2048) }
        val decoded = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) { "This photo could not be decoded." }
        val orientation = runCatching { ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val matrix = Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
            }
        }
        var oriented: Bitmap? = null
        var opaque: Bitmap? = null
        try {
            val rotated = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            oriented = rotated
            val exported = Bitmap.createBitmap(rotated.width, rotated.height, Bitmap.Config.ARGB_8888)
            opaque = exported
            Canvas(exported).apply { drawColor(Color.WHITE); drawBitmap(rotated, 0f, 0f, null) }
            val output = ByteArrayOutputStream()
            check(exported.compress(Bitmap.CompressFormat.JPEG, 88, output)) { "This photo could not be exported." }
            return output.toByteArray().also { require(it.isNotEmpty() && it.size <= 12 * 1024 * 1024) { "The exported photo exceeds 12 MiB." } }
        } finally { opaque?.recycle(); if (oriented !== decoded) oriented?.recycle(); decoded.recycle() }
    }
    fun display(bytes: ByteArray): Bitmap? {
        if (bytes.isEmpty() || bytes.size > 12 * 1024 * 1024) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth < 1 || bounds.outHeight < 1 || bounds.outWidth.toLong() * bounds.outHeight > 24_000_000) return null
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample(bounds.outWidth, bounds.outHeight, 1600) })
    }
    fun sample(width: Int, height: Int, edge: Int): Int {
        var sample = 1
        while (width / sample > edge || height / sample > edge) sample *= 2
        return sample
    }
}
