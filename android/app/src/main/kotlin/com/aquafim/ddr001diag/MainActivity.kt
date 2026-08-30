package com.aquafim.ddr001diag

import android.content.Intent
import android.content.ActivityNotFoundException
import android.app.Activity
import android.content.ClipData
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.MediaStore
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
    companion object {
        private const val DURABLE_CAMERA_REQUEST = 49172
        private const val DURABLE_CAMERA_CHANNEL =
            "com.aquafim.ddr001diag/durable_camera"
        private const val DURABLE_CAMERA_PREFS = "durable_camera_results_v1"
        private const val DIAGNOSTIC_EXPORT_REQUEST = 49173
        private const val DIAGNOSTIC_EXPORT_CHANNEL =
            "com.aquafim.ddr001diag/diagnostic_export"
    }

    private var cellularInternetProbeChannel: CellularInternetProbeChannel? = null
    private var cellularTelephonyChannel: CellularTelephonyChannel? = null
    private var apiDiagnosticsChannel: MethodChannel? = null
    private var appFilesChannel: MethodChannel? = null
    private var diagnosticReportChannel: MethodChannel? = null
    private var diagnosticExportChannel: MethodChannel? = null
    private var diagnosticExportResult: MethodChannel.Result? = null
    private var diagnosticExportSource: File? = null
    private var durableCameraChannel: MethodChannel? = null
    private var durableCameraResult: MethodChannel.Result? = null
    private var durableCameraId: String? = null
    private var durableCameraPath: String? = null

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
                val photoId = call.argument<String>("photoId")
                if (requested == null || photoId == null ||
                    !photoId.matches(Regex("^[A-Za-z0-9-]{1,80}$"))) {
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
                            // Durable, deterministic upload representation. It
                            // survives process death and is reused byte-for-byte
                            // for every retry of the same photoId.
                            val stagingDirectory = File(filesDir, "upload-representations")
                            if (!stagingDirectory.exists() && !stagingDirectory.mkdirs()) {
                                throw IllegalStateException("STAGING_DIRECTORY")
                            }
                            val staged = File(stagingDirectory, "$photoId.source")
                            FileInputStream(file).use { input ->
                                FileOutputStream(staged).use { output ->
                                    input.copyTo(output, bufferSize = 64 * 1024)
                                    output.fd.sync()
                                }
                            }
                            if (staged.length() != file.length()) {
                                throw IllegalStateException("STAGING_LENGTH")
                            }
                            val uploadFile = File(stagingDirectory, "$photoId.upload")
                            if (!uploadFile.exists() && staged.length() > 900_000L) {
                                val bitmap = BitmapFactory.decodeFile(staged.path)
                                    ?: throw IllegalStateException("STAGING_DECODE")
                                try {
                                    FileOutputStream(uploadFile).use { output ->
                                        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                                            throw IllegalStateException("STAGING_COMPRESS")
                                        }
                                        output.fd.sync()
                                    }
                                } finally {
                                    bitmap.recycle()
                                }
                                if (uploadFile.length() !in 1L..8_388_608L) {
                                    throw IllegalStateException("STAGING_NORMALIZED_LENGTH")
                                }
                            } else if (!uploadFile.exists()) {
                                FileInputStream(staged).use { input ->
                                    FileOutputStream(uploadFile).use { output ->
                                        input.copyTo(output, bufferSize = 64 * 1024)
                                        output.fd.sync()
                                    }
                                }
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
        diagnosticReportChannel = DiagnosticReportChannelFactory.configure(
            this,
            flutterEngine,
        )
        diagnosticExportChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIAGNOSTIC_EXPORT_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (diagnosticExportResult != null) {
                    result.error("EXPORT_IN_PROGRESS", "Ya existe una exportación activa.", null)
                    return@setMethodCallHandler
                }
                val report = ProductionDiagnosticExportPolicy.resolveReport(
                    filesDir,
                    getExternalFilesDir(null),
                    call.argument<String>("path"),
                )
                if (report == null) {
                    result.error("INVALID_REPORT", "Reporte inválido.", null)
                    return@setMethodCallHandler
                }
                val intent = ProductionDiagnosticExportPolicy.createDocumentIntent(report.name)
                diagnosticExportResult = result
                diagnosticExportSource = report
                try {
                    startActivityForResult(intent, DIAGNOSTIC_EXPORT_REQUEST)
                } catch (_: ActivityNotFoundException) {
                    diagnosticExportResult = null
                    diagnosticExportSource = null
                    result.error(
                        "EXPORT_UNAVAILABLE",
                        "No existe un selector de documentos.",
                        null,
                    )
                }
            }
        }
        durableCameraChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DURABLE_CAMERA_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> startDurableCameraCapture(call.arguments, result)
                    "status" -> {
                        val id = call.argument<String>("captureId")
                        if (!DurableCameraCapturePolicy.isValidCaptureId(id)) {
                            result.error("INVALID_CAPTURE", "Identidad de captura inválida.", null)
                        } else {
                            result.success(durableCameraPreferences().getString(id, null))
                        }
                    }
                    "clear" -> {
                        val id = call.argument<String>("captureId")
                        if (!DurableCameraCapturePolicy.isValidCaptureId(id)) {
                            result.error("INVALID_CAPTURE", "Identidad de captura inválida.", null)
                        } else {
                            val preferences = durableCameraPreferences()
                            val editor = preferences.edit().remove(id)
                            if (preferences.getString("activeCaptureId", null) == id) {
                                editor.remove("activeCaptureId").remove("activeCapturePath")
                            }
                            editor.commit()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun startDurableCameraCapture(arguments: Any?, result: MethodChannel.Result) {
        val preferences = durableCameraPreferences()
        if (durableCameraResult != null ||
            preferences.getString("activeCaptureId", null) != null) {
            result.error("CAPTURE_IN_PROGRESS", "Ya existe una captura activa.", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val values = arguments as? Map<String, Any?>
        val captureId = values?.get("captureId") as? String
        val requestedPath = values?.get("path") as? String
        if (!DurableCameraCapturePolicy.isValidCaptureId(captureId) ||
            requestedPath == null) {
            result.error("INVALID_CAPTURE", "Identidad de captura inválida.", null)
            return
        }
        var validatedDestination: File? = null
        try {
            val stagingRoot = File(filesDir, "camera-capture-staging").canonicalFile
            if (!stagingRoot.exists() && !stagingRoot.mkdirs()) {
                throw IllegalStateException("CAPTURE_DIRECTORY")
            }
            val destination = DurableCameraCapturePolicy.resolveDestination(
                filesDir,
                captureId,
                requestedPath,
            )
            if (destination == null || destination.parentFile != stagingRoot) {
                result.error("INVALID_CAPTURE_PATH", "Destino fuera del staging privado.", null)
                return
            }
            validatedDestination = destination
            if (destination.exists() && !destination.delete()) {
                throw IllegalStateException("CAPTURE_STALE_FILE")
            }
            if (!destination.createNewFile()) {
                throw IllegalStateException("CAPTURE_CREATE_FILE")
            }
            val uri = FileProvider.getUriForFile(
                this,
                DurableCameraCapturePolicy.authority(packageName),
                destination,
            )
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, uri)
                clipData = ClipData.newRawUri("durable-camera-output", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            }
            if (intent.resolveActivity(packageManager) == null) {
                destination.delete()
                result.error("CAMERA_UNAVAILABLE", "No existe una cámara compatible.", null)
                return
            }
            durableCameraResult = result
            durableCameraId = captureId
            durableCameraPath = destination.path
            durableCameraPreferences().edit()
                .putString(captureId, "launched")
                .putString("activeCaptureId", captureId)
                .putString("activeCapturePath", destination.path)
                .commit()
            startActivityForResult(intent, DURABLE_CAMERA_REQUEST)
        } catch (error: Exception) {
            preferences.edit()
                .remove(captureId)
                .remove("activeCaptureId")
                .remove("activeCapturePath")
                .commit()
            if (validatedDestination?.isFile == true) validatedDestination.delete()
            durableCameraResult = null
            durableCameraId = null
            durableCameraPath = null
            result.error("CAMERA_START_FAILED", error.javaClass.simpleName, null)
        }
    }

    @Deprecated("Activity result is intentionally persisted for process-death recovery")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DIAGNOSTIC_EXPORT_REQUEST) {
            finishDiagnosticExport(resultCode, data?.data)
            return
        }
        if (requestCode != DURABLE_CAMERA_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val preferences = durableCameraPreferences()
        val captureId = durableCameraId ?: preferences.getString("activeCaptureId", null)
        val path = durableCameraPath ?: preferences.getString("activeCapturePath", null)
        val file = DurableCameraCapturePolicy.resolveDestination(filesDir, captureId, path)
        val success = resultCode == Activity.RESULT_OK && file?.isFile == true && file.length() > 0
        if (file != null) {
            val uri = FileProvider.getUriForFile(
                this,
                DurableCameraCapturePolicy.authority(packageName),
                file,
            )
            revokeUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
        if (captureId != null) {
            preferences.edit()
                .putString(captureId, if (success) "success" else "canceled")
                .remove("activeCaptureId")
                .remove("activeCapturePath")
                .commit()
        }
        durableCameraResult?.success(if (success) path else null)
        durableCameraResult = null
        durableCameraId = null
        durableCameraPath = null
    }

    private fun finishDiagnosticExport(resultCode: Int, destination: Uri?) {
        val result = diagnosticExportResult
        val source = diagnosticExportSource
        diagnosticExportResult = null
        diagnosticExportSource = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || destination == null || source == null) {
            result.success(false)
            return
        }
        thread(name = "diagnostic-json-export") {
            try {
                contentResolver.openOutputStream(destination, "w").use { output ->
                    requireNotNull(output) { "EXPORT_OUTPUT" }
                    FileInputStream(source).use { input ->
                        input.copyTo(output, bufferSize = 64 * 1024)
                    }
                }
                runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("EXPORT_FAILED", error.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun durableCameraPreferences() =
        getSharedPreferences(DURABLE_CAMERA_PREFS, MODE_PRIVATE)

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
        diagnosticExportChannel?.setMethodCallHandler(null)
        diagnosticExportChannel = null
        diagnosticExportResult = null
        diagnosticExportSource = null
        durableCameraChannel?.setMethodCallHandler(null)
        durableCameraChannel = null
        durableCameraResult = null
        super.onDestroy()
    }
}

object ProductionDiagnosticExportPolicy {
    const val MIME_TYPE = "application/json"
    private const val MAX_REPORT_BYTES = 128L * 1024L * 1024L
    private val reportName = Regex("^DDR001_RV_DIAGNOSTIC_v60_[0-9TZ]+\\.json$")

    fun resolveReport(
        filesDir: File,
        externalFilesDir: File?,
        requestedPath: String?,
    ): File? {
        if (requestedPath.isNullOrBlank()) return null
        return try {
            val report = File(requestedPath).canonicalFile
            val allowedRoots = listOfNotNull(filesDir, externalFilesDir)
                .map { it.canonicalFile }
            if (
                report.isFile &&
                report.length() in 1L..MAX_REPORT_BYTES &&
                reportName.matches(report.name) &&
                allowedRoots.any { root ->
                    report.path.startsWith(root.path + File.separator)
                }
            ) report else null
        } catch (_: Exception) {
            null
        }
    }

    fun createDocumentIntent(fileName: String): Intent =
        Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = MIME_TYPE
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
}
