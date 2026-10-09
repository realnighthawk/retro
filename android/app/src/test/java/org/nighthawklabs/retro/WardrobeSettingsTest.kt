package org.nighthawklabs.retro

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import org.nighthawklabs.retro.data.*
import org.nighthawklabs.retro.net.*
import java.nio.file.Files

class WardrobeSettingsTest {
    private fun fixture(name: String) = javaClass.classLoader!!.getResource("$name.json")!!.readText()
    @Test fun preferencesKeepExactVersionsZeroAndFalse() {
        val p = ApiJson.decodeFromString<WardrobePreferencesResult>(fixture("preferences")).preferences
        assertEquals(9007199254740993L, p.version); assertEquals(0, p.avoid_repeat_days); assertFalse(p.prefer_underused_items)
        assertEquals(0, p.machine_presets[0].temperature_c)
        val patch = WardrobeSettingFields.patch(ApiJson.encodeToJsonElement(WardrobePreferences.serializer(), p).jsonObject, WardrobeSettingFields.preferences)
        assertNull(patch["id"]); assertEquals(0, patch["avoid_repeat_days"]!!.jsonPrimitive.int)
        assertTrue(runCatching { WardrobeSettingFields.validate(buildJsonObject { put("cold_threshold_c", "bad") }, listOf("cold_threshold_c")) }.isFailure)
    }
    @Test fun feedbackResetsAreExplicitAndOldFeedbackKeepsReviewedVersion() {
        val r = ApiJson.decodeFromString<WardrobeFeedbackResult>(fixture("feedback"))
        assertNull(r.feedback.rating); assertNotEquals(r.feedback.outfit_version, r.current_outfit_version)
        val patch = WardrobeSettingFields.patch(buildJsonObject { put("warmth", "unknown") }, WardrobeSettingFields.feedback)
        assertEquals(JsonNull, patch["rating"])
        assertTrue(runCatching { WardrobeSettingFields.validate(buildJsonObject { put("rating", 0) }, listOf("rating")) }.isFailure)
    }
    @Test fun careAndThresholdsRequireConsistentReviewedValues() {
        val old = ApiJson.decodeFromString<WardrobePage<WardrobeGarment>>(fixture("inventory"))
        assertNull(old.items.first().care)
        val unknown = buildJsonObject { put("wash_method", "unknown"); put("confirmed", true) }
        assertTrue(runCatching { WardrobeSettingFields.validate(unknown, WardrobeSettingFields.care) }.isFailure)
        val nonWash = buildJsonObject { put("wash_method", "dry_clean"); put("max_temp_c", 30) }
        assertTrue(runCatching { WardrobeSettingFields.validate(nonWash, listOf("wash_method", "max_temp_c")) }.isFailure)
        val thresholds = buildJsonObject { put("cold_threshold_c", 25); put("hot_threshold_c", 25) }
        assertTrue(runCatching { WardrobeSettingFields.validate(thresholds, listOf("cold_threshold_c", "hot_threshold_c")) }.isFailure)
        val coldWash = buildJsonObject { put("wash_method", "machine"); put("max_temp_c", 0); put("cycle", "gentle"); put("confirmed", true) }
        WardrobeSettingFields.validate(coldWash, listOf("wash_method", "max_temp_c", "cycle", "confirmed"))
    }
    @Test fun feedbackWriteSurvivesReopeningWithFrozenVersions() {
        val root = Files.createTempDirectory("retro-settings").toFile()
        try {
            val file = root.resolve("writes.json")
            val writes = WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) })
            val id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
            writes.enqueue("outfits_feedback_update", id, "Feedback", buildJsonObject {
                put("id", id); put("expected_version", 0); put("outfit_id", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
                put("expected_outfit_version", 9007199254740993L); put("patch", buildJsonObject { put("rating", JsonNull) })
            })
            val restored = WardrobeWrites(file, { true }, { _, _ -> Api.Ok(true) })
            assertEquals(writes.items.first().body, restored.items.first().body)
            assertEquals(9007199254740993L, restored.items.first().body["expected_outfit_version"]!!.jsonPrimitive.long)
            assertEquals(0, restored.items.first().body["expected_version"]!!.jsonPrimitive.int)
        } finally { root.deleteRecursively() }
    }
}
