package com.aquafim.ddr001diag

import android.content.Intent
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
class ProductionDiagnosticExportPolicyTest {
    @Test
    fun `create document intent is local json without uri grants`() {
        val intent = ProductionDiagnosticExportPolicy.createDocumentIntent(
            "DDR001_RV_DIAGNOSTIC_v60_20260829T220000Z.json",
        )

        assertEquals(Intent.ACTION_CREATE_DOCUMENT, intent.action)
        assertEquals("application/json", intent.type)
        assertTrue(intent.categories?.contains(Intent.CATEGORY_OPENABLE) == true)
        assertEquals(
            "DDR001_RV_DIAGNOSTIC_v60_20260829T220000Z.json",
            intent.getStringExtra(Intent.EXTRA_TITLE),
        )
        assertFalse(intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0)
        assertFalse(intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
    }

    @Test
    fun `only bounded generated diagnostics inside app roots are accepted`() {
        val root = Files.createTempDirectory("production-diagnostic-export").toFile()
        val filesDir = File(root, "files").apply { mkdirs() }
        val externalDir = File(root, "external").apply { mkdirs() }
        val valid = File(
            externalDir,
            "DDR001_RV_DIAGNOSTIC_v60_20260829T220000Z.json",
        ).apply { writeText("{}") }
        val certificate = File(
            externalDir,
            "DDR001_RV_CERT_POST_RECOVERY_OFFLINE_20260829T220000Z.json",
        ).apply { writeText("{}") }
        val unrelated = File(externalDir, "photo.jpg").apply { writeText("x") }
        val outside = File(root, valid.name).apply { writeText("{}") }

        assertEquals(
            valid.canonicalFile,
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                externalDir,
                valid.path,
            ),
        )
        assertNull(
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                externalDir,
                certificate.path,
            ),
        )
        assertNull(
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                externalDir,
                unrelated.path,
            ),
        )
        assertNull(
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                externalDir,
                outside.path,
            ),
        )

        root.deleteRecursively()
    }

    @Test
    fun `accepts current forensic corpus and rejects oversized report`() {
        val root = Files.createTempDirectory("production-diagnostic-size").toFile()
        val filesDir = File(root, "files").apply { mkdirs() }
        val current = File(
            filesDir,
            "DDR001_RV_DIAGNOSTIC_v60_20260829T220002Z.json",
        ).apply {
            writeText("x")
            java.io.RandomAccessFile(this, "rw").use {
                it.setLength(103_000_000L)
            }
        }
        val oversized = File(
            filesDir,
            "DDR001_RV_DIAGNOSTIC_v60_20260829T220003Z.json",
        ).apply {
            writeText("x")
            java.io.RandomAccessFile(this, "rw").use {
                it.setLength(134_217_729L)
            }
        }

        assertEquals(
            current.canonicalFile,
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                null,
                current.path,
            ),
        )
        assertNull(
            ProductionDiagnosticExportPolicy.resolveReport(
                filesDir,
                null,
                oversized.path,
            ),
        )

        root.deleteRecursively()
    }
}
