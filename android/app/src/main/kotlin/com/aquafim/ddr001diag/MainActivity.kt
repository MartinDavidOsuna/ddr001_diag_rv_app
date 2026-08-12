package com.aquafim.ddr001diag

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cellularInternetProbeChannel: CellularInternetProbeChannel? = null
    private var cellularTelephonyChannel: CellularTelephonyChannel? = null
    private var apiDiagnosticsChannel: MethodChannel? = null

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
        apiDiagnosticsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aquafim.ddr001diag/api_diagnostics",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "log") {
                    Log.w("DDR001_API", call.arguments?.toString() ?: "-")
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        cellularInternetProbeChannel?.dispose()
        cellularInternetProbeChannel = null
        cellularTelephonyChannel?.dispose()
        cellularTelephonyChannel = null
        apiDiagnosticsChannel?.setMethodCallHandler(null)
        apiDiagnosticsChannel = null
        super.onDestroy()
    }
}
