package com.aquafim.ddr001diag

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Production deliberately exposes no QA report channel. */
object DiagnosticReportChannelFactory {
    fun configure(
        activity: MainActivity,
        flutterEngine: FlutterEngine,
    ): MethodChannel? = null
}
