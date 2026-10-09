package org.nighthawklabs.retro

import android.app.Application
import org.nighthawklabs.retro.auth.Auth

class RetroApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Auth.init(this)
    }
}
