package com.aquafim.ddr001diag

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLException

class CellularInternetProbeChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL_NAME = "com.aquafim.ddr001diag/cellular_internet_probe"
    }

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var activeProbe: ActiveProbe? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startProbe" -> startProbe(call, result)
            "cancelProbe" -> {
                val probeId = call.argument<String>("probeId")
                cancelActive(probeId, deliverCancelled = true)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startProbe(call: MethodCall, result: MethodChannel.Result) {
        val probeId = call.argument<String>("probeId") ?: run {
            result.error("invalidArguments", "Falta probeId.", null)
            return
        }
        val url = call.argument<String>("url") ?: run {
            result.error("invalidArguments", "Falta URL de prueba.", null)
            return
        }
        cancelActive(null, deliverCancelled = true)
        val probe = ActiveProbe(
            id = probeId,
            result = result,
            url = url,
            httpMethod = call.argument<String>("httpMethod") ?: "GET",
            expectedStatusCode = call.argument<Int>("expectedStatusCode") ?: 204,
            connectTimeoutMs = call.argument<Int>("connectTimeoutMs") ?: 12_000,
            readTimeoutMs = call.argument<Int>("readTimeoutMs") ?: 12_000,
            networkTimeoutMs = (call.argument<Int>("networkTimeoutMs") ?: 60_000).coerceAtMost(60_000),
            maximumResponseBytes = call.argument<Int>("maximumResponseBytes") ?: 1024,
            methodVersion = call.argument<String>("methodVersion") ?: "unknown",
        )
        synchronized(lock) { activeProbe = probe }
        emitProgress(probe, "requestingCellularNetwork")
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .build()
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (!probe.isActive() || probe.task != null) return
                probe.networkAcquired = true
                emitProgress(probe, "verifyingCapabilities")
                val capabilities = connectivityManager.getNetworkCapabilities(network)
                probe.transportCellularConfirmed =
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
                probe.internetCapabilityPresent =
                    capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                probe.validatedCapabilityPresent =
                    capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                emitProgress(probe, "testingInternet")
                probe.task = executor.submit { executeHttpProbe(probe, network) }
            }

            override fun onUnavailable() {
                // La ausencia solo es concluyente al completar los 60 segundos.
                emitProgress(probe, "waitingForAvailability")
            }

            override fun onLost(network: Network) {
                if (probe.isActive() && probe.networkAcquired && !probe.probeAttempted) {
                    finish(
                        probe,
                        outcome = "cellularNetworkAvailableInternetNotConfirmed",
                        errorCode = "cellularNetworkLost",
                        errorMessage = "La red celular se perdió antes de completar la prueba.",
                    )
                }
            }
        }
        probe.callback = callback
        emitProgress(probe, "waitingForAvailability")
        try {
            connectivityManager.requestNetwork(request, callback)
            probe.timeoutRunnable = Runnable {
                if (probe.isActive()) {
                    finish(
                        probe,
                        outcome = if (probe.networkAcquired) "timeout" else "cellularNetworkUnavailable",
                        errorCode = if (probe.networkAcquired) "cellularHttpTimeout" else "cellularNetworkTimeout",
                        errorMessage = if (probe.networkAcquired)
                            "Se obtuvo la red celular, pero la prueba HTTP no concluyó en 60 segundos."
                        else
                            "No se obtuvo una red celular durante 60 segundos.",
                        timeoutReached = true,
                    )
                }
            }.also { mainHandler.postDelayed(it, probe.networkTimeoutMs.toLong()) }
        } catch (security: SecurityException) {
            finish(probe, "platformRestricted", "securityRestriction", security.message)
        } catch (error: Exception) {
            finish(probe, "indeterminate", "requestNetworkError", error.message)
        }
    }

    private fun executeHttpProbe(probe: ActiveProbe, network: Network) {
        var connection: HttpURLConnection? = null
        try {
            if (!probe.isActive()) return
            probe.probeAttempted = true
            val target = URL(probe.url)
            probe.host = target.host
            val started = System.nanoTime()
            connection = network.openConnection(target) as HttpURLConnection
            probe.connection = connection
            connection.instanceFollowRedirects = false
            connection.requestMethod = probe.httpMethod
            connection.connectTimeout = probe.connectTimeoutMs
            connection.readTimeout = probe.readTimeoutMs
            connection.useCaches = false
            connection.setRequestProperty("User-Agent", "DDR001-CellularProbe/${probe.methodVersion}")
            connection.connect()
            val statusCode = connection.responseCode
            probe.httpStatusCode = statusCode
            probe.responseReceived = true
            probe.latencyMs = ((System.nanoTime() - started) / 1_000_000L).toInt()
            emitProgress(probe, "measuringResponse")
            probe.bytesReceived = if (probe.httpMethod.equals("HEAD", ignoreCase = true)) {
                0
            } else {
                readLimited(connection, probe.maximumResponseBytes)
            }
            emitProgress(probe, "calculatingResult")
            if (statusCode == probe.expectedStatusCode) {
                finish(probe, "cellularInternetConfirmed")
            } else {
                finish(
                    probe,
                    "unexpectedHttpResponse",
                    "unexpectedHttpResponse",
                    "El endpoint respondió HTTP $statusCode; la red celular sí fue adquirida.",
                )
            }
        } catch (timeout: SocketTimeoutException) {
            finish(probe, "timeout", "httpTimeout", timeout.message)
        } catch (tls: SSLException) {
            finish(probe, "tlsError", "tlsError", tls.message)
        } catch (io: IOException) {
            finish(probe, "endpointUnavailable", "endpointUnavailable", io.message)
        } catch (error: Exception) {
            finish(probe, "indeterminate", "httpProbeError", error.message)
        } finally {
            connection?.disconnect()
            if (probe.connection === connection) probe.connection = null
        }
    }

    private fun readLimited(connection: HttpURLConnection, maximumBytes: Int): Int {
        val stream = try {
            connection.inputStream
        } catch (_: IOException) {
            connection.errorStream ?: return 0
        }
        stream.use { input ->
            val buffer = ByteArray(256)
            var total = 0
            while (total < maximumBytes) {
                val count = input.read(buffer, 0, minOf(buffer.size, maximumBytes - total))
                if (count < 0) break
                total += count
            }
            return total
        }
    }

    private fun emitProgress(probe: ActiveProbe, stage: String) {
        if (!probe.isActive()) return
        mainHandler.post {
            if (probe.isActive()) {
                channel.invokeMethod("probeProgress", mapOf("probeId" to probe.id, "stage" to stage))
            }
        }
    }

    private fun finish(
        probe: ActiveProbe,
        outcome: String,
        errorCode: String? = null,
        errorMessage: String? = null,
        timeoutReached: Boolean = false,
    ) {
        if (!probe.finished.compareAndSet(false, true)) return
        cleanup(probe)
        val completedAt = System.currentTimeMillis()
        val payload = hashMapOf<String, Any?>(
            "requestedCellularNetwork" to true,
            "cellularNetworkAcquired" to probe.networkAcquired,
            "transportCellularConfirmed" to probe.transportCellularConfirmed,
            "internetCapabilityPresent" to probe.internetCapabilityPresent,
            "validatedCapabilityPresent" to probe.validatedCapabilityPresent,
            "probeAttempted" to probe.probeAttempted,
            "probeUrlHost" to probe.host,
            "httpMethod" to probe.httpMethod,
            "httpStatusCode" to probe.httpStatusCode,
            "responseReceived" to probe.responseReceived,
            "latencyMs" to probe.latencyMs,
            "bytesReceived" to probe.bytesReceived,
            "startedAt" to isoTimestamp(probe.startedAt),
            "completedAt" to isoTimestamp(completedAt),
            "timeoutReached" to timeoutReached,
            "result" to outcome,
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
            "platform" to "android",
            "methodVersion" to probe.methodVersion,
        )
        mainHandler.post { probe.result.success(payload) }
    }

    private fun cancelActive(probeId: String?, deliverCancelled: Boolean) {
        val probe = synchronized(lock) {
            activeProbe?.takeIf { probeId == null || it.id == probeId }
        } ?: return
        if (deliverCancelled) {
            finish(probe, "cancelled", "cancelled", "La prueba celular fue cancelada.")
        } else if (probe.finished.compareAndSet(false, true)) {
            cleanup(probe)
        }
    }

    private fun isoTimestamp(milliseconds: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(milliseconds))

    private fun cleanup(probe: ActiveProbe) {
        probe.timeoutRunnable?.let(mainHandler::removeCallbacks)
        probe.timeoutRunnable = null
        probe.connection?.disconnect()
        probe.connection = null
        probe.task?.cancel(true)
        probe.task = null
        probe.callback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // Ya estaba retirado.
            }
        }
        probe.callback = null
        synchronized(lock) {
            if (activeProbe === probe) activeProbe = null
        }
    }

    fun dispose() {
        cancelActive(null, deliverCancelled = false)
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private inner class ActiveProbe(
        val id: String,
        val result: MethodChannel.Result,
        val url: String,
        val httpMethod: String,
        val expectedStatusCode: Int,
        val connectTimeoutMs: Int,
        val readTimeoutMs: Int,
        val networkTimeoutMs: Int,
        val maximumResponseBytes: Int,
        val methodVersion: String,
    ) {
        val startedAt = System.currentTimeMillis()
        val finished = AtomicBoolean(false)
        var callback: ConnectivityManager.NetworkCallback? = null
        var timeoutRunnable: Runnable? = null
        var task: Future<*>? = null
        var connection: HttpURLConnection? = null
        var networkAcquired = false
        var transportCellularConfirmed = false
        var internetCapabilityPresent: Boolean? = null
        var validatedCapabilityPresent: Boolean? = null
        var probeAttempted = false
        var host: String? = null
        var httpStatusCode: Int? = null
        var responseReceived = false
        var latencyMs: Int? = null
        var bytesReceived: Int? = null

        fun isActive(): Boolean = !finished.get() && synchronized(lock) { activeProbe === this }
    }
}
