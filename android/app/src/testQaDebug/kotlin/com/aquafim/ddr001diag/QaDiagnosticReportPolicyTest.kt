package com.aquafim.ddr001diag

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.nio.file.Files

@RunWith(RobolectricTestRunner::class)
class QaDiagnosticReportPolicyTest {
    @Test
    fun `share intent grants the same content uri through stream and clip data`() {
        val uri = Uri.parse(
            "content://com.aquafim.ddr001diag.qa.diagnostic.files/" +
                "qa_bootstrap_reports/qa_bootstrap_comparison_123.json",
        )

        val intent = QaDiagnosticReportPolicy.createShareIntent(uri)

        assertEquals(Intent.ACTION_SEND, intent.action)
        assertEquals("application/json", intent.type)
        assertEquals(uri, intent.getParcelableExtra(Intent.EXTRA_STREAM))
        assertEquals(1, intent.clipData?.itemCount)
        assertEquals(uri, intent.clipData?.getItemAt(0)?.uri)
        assertTrue(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertFalse(intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
        assertFalse(uri.scheme == "file")
    }

    @Test
    fun `authority is derived from the qa application id`() {
        assertEquals(
            "com.aquafim.ddr001diag.qa.diagnostic.files",
            QaDiagnosticReportPolicy.authority("com.aquafim.ddr001diag.qa"),
        )
    }

    @Test
    fun `only generated json reports directly inside the qa report root are accepted`() {
        val root = Files.createTempDirectory("qa-report-policy").toFile()
        val filesDir = File(root, "files").apply { mkdirs() }
        val reports = File(filesDir, QaDiagnosticReportPolicy.REPORT_DIRECTORY)
            .apply { mkdirs() }
        val valid = File(reports, "qa_bootstrap_comparison_123.json")
            .apply { writeText("{}") }
        val unrelated = File(reports, "evidence.jpg").apply { writeText("x") }
        val outside = File(filesDir, "qa_bootstrap_comparison_456.json")
            .apply { writeText("{}") }

        assertEquals(
            valid.canonicalFile,
            QaDiagnosticReportPolicy.resolveReport(filesDir, valid.path),
        )
        assertNull(QaDiagnosticReportPolicy.resolveReport(filesDir, unrelated.path))
        assertNull(QaDiagnosticReportPolicy.resolveReport(filesDir, outside.path))
        assertNull(
            QaDiagnosticReportPolicy.resolveReport(
                filesDir,
                File(reports, "../qa_bootstrap_comparison_456.json").path,
            ),
        )

        root.deleteRecursively()
    }
}
