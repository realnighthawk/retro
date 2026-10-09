package org.nighthawklabs.retro

/**
 * DEBUG builds only: launching the app with the intent extra `dev_engine` (for the emulator, http://10.0.2.2:18091)
 * points it straight at a local /retro private wardrobe engine, skipping Clerk and the router. `dev_hour`
 * pins the clock so the day arc can be seen at a chosen hour. Release builds ignore both.
 */
object DevMode {
    @Volatile var engineUrl: String? = null
        private set

    @Volatile var demoHour: Int? = null
        private set

    /** `dev_tab <today|wardrobe|history>` opens straight onto one surface. */
    @Volatile var surface: String? = null
        private set

    fun configure(engine: String?, hour: Int?, surface: String?) {
        engineUrl = if (BuildConfig.DEBUG) engine?.takeIf { it.isNotBlank() } else null
        demoHour = if (BuildConfig.DEBUG) hour?.coerceIn(0, 23) else null
        this.surface = if (BuildConfig.DEBUG) surface?.takeIf { it.isNotBlank() } else null
    }

    const val USER = "dev_user"
}
