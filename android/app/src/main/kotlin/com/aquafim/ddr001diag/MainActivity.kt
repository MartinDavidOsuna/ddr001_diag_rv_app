package com.aquafim.ddr001diag

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var cellularInternetProbeChannel: CellularInternetProbeChannel? = null
    private var cellularTelephonyChannel: CellularTelephonyChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cellularInternetProbeChannel = CellularInternetProbeChannel(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        cellularTelephonyChannel = CellularTelephonyChannel(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        cellularInternetProbeChannel?.dispose()
        cellularInternetProbeChannel = null
        cellularTelephonyChannel?.dispose()
        cellularTelephonyChannel = null
        super.onDestroy()
    }
}
