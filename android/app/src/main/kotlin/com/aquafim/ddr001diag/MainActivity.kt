package com.aquafim.ddr001diag

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.concurrent.thread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cellularInternetProbeChannel: CellularInternetProbeChannel? = null
    private var cellularTelephonyChannel: CellularTelephonyChannel? = null
    private var apiDiagnosticsChannel: MethodChannel? = null
    private var appFilesChannel: MethodChannel? = null
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
        appFilesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aquafim.ddr001diag/app_files",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "stage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val requested = call.argument<String>("path")
                if (requested == null) {
                    result.error("INVALID_PATH", "Ruta ausente", null)
                    return@setMethodCallHandler
                }
                thread(name = "app-file-reader") {
                    try {
                        val file = File(requested).canonicalFile
                        val root = applicationInfo.dataDir?.let(::File)?.canonicalFile
                        val allowed = root != null &&
                            file.path.startsWith(root.path + File.separator) &&
                            file.isFile && file.length() in 1L..8_388_608L
                        if (!allowed) {
                            runOnUiThread {
                                result.error("INVALID_PATH", "Archivo fuera del almacenamiento privado", null)
                            }
                        } else {
                            // Return only a path through the platform channel. Sending a
                            // multi-megabyte ByteArray makes Flutter's Android UI thread
                            // encode the whole image and can trigger an input-dispatch ANR.
                            val stagingDirectory = File(cacheDir, "sync-staging")
                            if (!stagingDirectory.exists() && !stagingDirectory.mkdirs()) {
                                throw IllegalStateException("STAGING_DIRECTORY")
                            }
                            val staged = File.createTempFile("photo-", ".upload", stagingDirectory)
                            FileInputStream(file).use { input ->
                                FileOutputStream(staged).use { output ->
                                    input.copyTo(output, bufferSize = 64 * 1024)
                                    output.fd.sync()
                                }
                            }
                            if (staged.length() != file.length()) {
                                throw IllegalStateException("STAGING_LENGTH")
                            }
                            var uploadFile = staged
                            if (staged.length() > 900_000L) {
                                val bitmap = BitmapFactory.decodeFile(staged.path)
                                    ?: throw IllegalStateException("STAGING_DECODE")
                                val normalized = File.createTempFile(
                                    "photo-normalized-", ".jpg", stagingDirectory
                                )
                                FileOutputStream(normalized).use { output ->
                                    if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                                        throw IllegalStateException("STAGING_COMPRESS")
                                    }
                                    output.fd.sync()
                                }
                                bitmap.recycle()
                                if (normalized.length() !in 1L..8_388_608L) {
                                    throw IllegalStateException("STAGING_NORMALIZED_LENGTH")
                                }
                                uploadFile = normalized
                            }
                            runOnUiThread {
                                result.success(
                                    mapOf(
                                        "sourcePath" to staged.path,
                                        "uploadPath" to uploadFile.path,
                                    )
                                )
                            }
                        }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("READ_FAILED", error.javaClass.simpleName, null)
                        }
                    }
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
        appFilesChannel?.setMethodCallHandler(null)
        appFilesChannel = null
        diagnosticReportChannel?.setMethodCallHandler(null)
        diagnosticReportChannel = null
        super.onDestroy()
    }
}
