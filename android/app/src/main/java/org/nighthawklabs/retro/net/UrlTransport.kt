package org.nighthawklabs.retro.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

object UrlTransport : Transport {
    override suspend fun request(method: String, url: String, token: String, body: String?, timeoutMs: Int): Pair<Int, String>? =
        withContext(Dispatchers.IO) {
            var conn: HttpURLConnection? = null
            try {
                val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = 15_000
                    readTimeout = timeoutMs
                    doOutput = body != null
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "application/json")
                }
                conn = connection
                if (body != null) connection.outputStream.use { it.write(body.toByteArray()) }
                val code = connection.responseCode
                val text = (if (code in 200..299) connection.inputStream else connection.errorStream)
                    ?.bufferedReader()?.use { it.readText() }.orEmpty()
                code to text
            } catch (e: IOException) {
                null
            } finally {
                conn?.disconnect()
            }
        }
}

/** Binary traffic stays on the configured origin; redirects must never carry Clerk credentials elsewhere. */
object PhotoTransport : BinaryTransport {
    override suspend fun requestBytes(method: String, url: String, token: String, body: ByteArray?): Pair<Int, ByteArray>? =
        withContext(Dispatchers.IO) {
            var conn: HttpURLConnection? = null
            try {
                val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = method; instanceFollowRedirects = false; useCaches = false
                    connectTimeout = 15_000; readTimeout = 30_000; doOutput = body != null
                    setRequestProperty("Authorization", "Bearer $token")
                    setRequestProperty("Content-Type", "image/jpeg")
                    if (body != null) setFixedLengthStreamingMode(body.size)
                }
                conn = connection
                if (body != null) connection.outputStream.use { it.write(body) }
                val code = connection.responseCode
                val data = (if (code in 200..299) connection.inputStream else connection.errorStream)?.use { stream ->
                    val result = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        if (result.size() + read > 12 * 1024 * 1024) throw IOException("Photo is too large")
                        result.write(buffer, 0, read)
                    }
                    result.toByteArray()
                } ?: ByteArray(0)
                code to data
            } catch (_: IOException) { null } finally { conn?.disconnect() }
        }
}
