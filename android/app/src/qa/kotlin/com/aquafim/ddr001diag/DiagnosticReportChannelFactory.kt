package com.aquafim.ddr001diag

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Native channel compiled only into the isolated QA flavor. */
object DiagnosticReportChannelFactory {
    private const val CHANNEL = "com.aquafim.ddr001diag/diagnostic_report"

    fun configure(
        activity: MainActivity,
        flutterEngine: FlutterEngine,
    ): MethodChannel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        CHANNEL,
    ).also { channel ->
        channel.setMethodCallHandler { call, result ->
            if (call.method != "share") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val report = QaDiagnosticReportPolicy.resolveReport(
                activity.filesDir,
                call.argument<String>("path"),
            )
            if (report == null) {
                result.error("INVALID_REPORT", "Reporte inválido", null)
                return@setMethodCallHandler
            }
            try {
                val uri = FileProvider.getUriForFile(
                    activity,
                    QaDiagnosticReportPolicy.authority(activity.packageName),
                    report,
                )
                val shareIntent = QaDiagnosticReportPolicy.createShareIntent(uri)
                val chooser = Intent.createChooser(
                    shareIntent,
                    "Compartir reporte QA",
                ).apply {
                    clipData = shareIntent.clipData
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                activity.startActivity(chooser)
                result.success(null)
            } catch (error: Exception) {
                result.error(
                    "REPORT_SHARE_FAILED",
                    error.javaClass.simpleName,
                    null,
                )
            }
        }
    }
}

object QaDiagnosticReportPolicy {
    const val MIME_TYPE = "application/json"
    const val REPORT_DIRECTORY = "qa-diagnostic-reports"
    private val reportName = Regex("^qa_bootstrap_comparison_[0-9]+\\.json$")

    fun authority(packageName: String): String = "$packageName.diagnostic.files"

    fun resolveReport(filesDir: File, requestedPath: String?): File? {
        if (requestedPath.isNullOrBlank()) return null
        return try {
            val root = File(filesDir, REPORT_DIRECTORY).canonicalFile
            val report = File(requestedPath).canonicalFile
            if (
                report.parentFile == root &&
                reportName.matches(report.name) &&
                report.isFile
            ) {
                report
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    fun createShareIntent(contentUri: Uri): Intent =
        Intent(Intent.ACTION_SEND).apply {
            type = MIME_TYPE
            putExtra(Intent.EXTRA_STREAM, contentUri)
            clipData = ClipData.newRawUri("DDR001 RV QA report", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
}
