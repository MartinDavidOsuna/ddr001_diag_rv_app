package com.aquafim.ddr001diag

import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cellularInternetProbeChannel: CellularInternetProbeChannel? = null
    private var cellularTelephonyChannel: CellularTelephonyChannel? = null
    private var apiDiagnosticsChannel: MethodChannel? = null
    private var diagnosticReportChannel: MethodChannel? = null

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
        diagnosticReportChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aquafim.ddr001diag/diagnostic_report").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "share") { result.notImplemented(); return@setMethodCallHandler }
                val report = call.argument<String>("path")?.let(::File)
                val allowedParents = listOfNotNull(cacheDir, getExternalFilesDir(null))
                if (report == null || !report.isFile || report.parentFile !in allowedParents) { result.error("INVALID_REPORT", "Reporte inválido", null); return@setMethodCallHandler }
                val uri = FileProvider.getUriForFile(this, "$packageName.diagnostic.files", report)
                val intent = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                startActivity(Intent.createChooser(intent, "Compartir reporte")); result.success(null)
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
        diagnosticReportChannel?.setMethodCallHandler(null)
        diagnosticReportChannel = null
        super.onDestroy()
    }
}
