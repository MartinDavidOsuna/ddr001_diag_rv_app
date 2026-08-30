package com.aquafim.ddr001diag

import java.io.File

/** Pure validation shared by the Android camera channel and JVM tests. */
internal object DurableCameraCapturePolicy {
    private val captureIdPattern = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$",
    )

    fun isValidCaptureId(value: String?): Boolean =
        value != null && captureIdPattern.matches(value)

    fun authority(packageName: String): String = "$packageName.diagnostic.files"

    /**
     * Returns the exact preassigned destination or null. Canonicalizing both
     * sides rejects traversal and symlinks that resolve outside the staging
     * directory. The filename is derived from the validated capture ID.
     */
    fun resolveDestination(filesDir: File, captureId: String?, requestedPath: String?): File? {
        if (!isValidCaptureId(captureId) || requestedPath == null) return null
        val stagingRoot = File(filesDir, "camera-capture-staging").canonicalFile
        val expected = File(stagingRoot, "$captureId.source.jpg").canonicalFile
        val requested = File(requestedPath).canonicalFile
        if (expected.parentFile != stagingRoot || requested != expected) return null
        return expected
    }
}
