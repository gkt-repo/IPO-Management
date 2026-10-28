package com.ipo.tracker.ipo_tracker

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setHighRefreshRate()
    }

    private fun setHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val currentDisplay = display ?: return
            val modes = currentDisplay.supportedModes
            val targetMode = modes.firstOrNull { it.refreshRate.toInt() == 120 }
                ?: modes.maxByOrNull { it.refreshRate }

            targetMode?.let {
                val params = window.attributes
                params.preferredDisplayModeId = it.modeId
                window.attributes = params
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val params = window.attributes
            params.preferredRefreshRate = 120.0f
            window.attributes = params
        }
    }
}
