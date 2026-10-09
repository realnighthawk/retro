package org.nighthawklabs.retro.data

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/** Re-fetchable reads only. Pending mutations will need error-reporting durable storage separately. */
class WardrobeReadCache(root: File, owner: String, private val service: String) {
    private val directory = File(File(root, "retro"), digest(owner))
    private fun file(key: String) = File(directory, digest("$service\n$key") + ".json")

    fun read(key: String): String? = runCatching { file(key).readText() }.getOrNull()

    fun write(key: String, json: String) {
        var temporary: File? = null
        try {
            if (!directory.isDirectory && !directory.mkdirs()) return
            val pending = File.createTempFile("read-", ".tmp", directory)
            temporary = pending
            pending.writeText(json)
            Files.move(pending.toPath(), file(key).toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: Exception) {
            // A missing read cache can be fetched again; never use this best-effort path for a saved edit.
        } finally { temporary?.delete() }
    }

    fun clear() { directory.deleteRecursively() }

    private fun digest(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
}
