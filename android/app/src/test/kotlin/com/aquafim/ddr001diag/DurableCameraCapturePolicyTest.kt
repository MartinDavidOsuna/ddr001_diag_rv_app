package com.aquafim.ddr001diag

import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DurableCameraCapturePolicyTest {
    private lateinit var root: File
    private val captureId = "123e4567-e89b-42d3-a456-426614174000"

    @Before
    fun setUp() {
        root = Files.createTempDirectory("durable-camera-policy").toFile()
        File(root, "camera-capture-staging").mkdirs()
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun acceptsOnlyExactPreassignedDestination() {
        val expected = File(root, "camera-capture-staging/$captureId.source.jpg")
        assertEquals(
            expected.canonicalFile,
            DurableCameraCapturePolicy.resolveDestination(root, captureId, expected.path),
        )
    }

    @Test
    fun rejectsTraversalOutsideAndMaliciousIdentifiers() {
        val outside = File(root, "outside.jpg")
        assertNull(
            DurableCameraCapturePolicy.resolveDestination(
                root,
                captureId,
                File(root, "camera-capture-staging/../outside.jpg").path,
            ),
        )
        assertNull(
            DurableCameraCapturePolicy.resolveDestination(
                root,
                "../../preferences",
                outside.path,
            ),
        )
        assertFalse(DurableCameraCapturePolicy.isValidCaptureId("activeCaptureId"))
    }

    @Test
    fun rejectsSymlinkThatEscapesStagingWhenSupported() {
        val outside = File(root, "outside.jpg").apply { writeText("evidence") }
        val link = File(root, "camera-capture-staging/$captureId.source.jpg")
        try {
            Files.createSymbolicLink(link.toPath(), outside.toPath())
        } catch (_: UnsupportedOperationException) {
            return
        } catch (_: SecurityException) {
            return
        }
        assertNull(
            DurableCameraCapturePolicy.resolveDestination(root, captureId, link.path),
        )
    }

    @Test
    fun authoritiesRemainFlavorSpecific() {
        assertEquals(
            "com.aquafim.ddr001diag.diagnostic.files",
            DurableCameraCapturePolicy.authority("com.aquafim.ddr001diag"),
        )
        assertEquals(
            "com.aquafim.ddr001diag.qa.diagnostic.files",
            DurableCameraCapturePolicy.authority("com.aquafim.ddr001diag.qa"),
        )
        assertTrue(DurableCameraCapturePolicy.isValidCaptureId(captureId))
    }
}
