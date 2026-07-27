package com.aquafim.ddr001diag

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.telephony.CellSignalStrength
import android.telephony.CellInfo
import android.telephony.ServiceState
import android.telephony.SignalStrength
import android.telephony.SubscriptionManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A short-lived telephony snapshot. It never reads or returns IMSI, ICCID,
 * phone number, cell identity, or another permanent subscriber identifier.
 */
class CellularTelephonyChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val mainExecutor = context.mainExecutor
    private var activeCapture: Capture? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> startCapture(result)
            else -> result.notImplemented()
        }
    }

    private fun startCapture(result: MethodChannel.Result) {
        if (activeCapture != null) {
            result.error("capture_in_progress", "Ya existe una captura de telefonía.", null)
            return
        }

        val permissionGranted =
            context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
                PackageManager.PERMISSION_GRANTED
        if (!permissionGranted) {
            result.success(
                baseResult(
                    availabilityReason = "permission_denied",
                    transportType = currentTransport(),
                ),
            )
            return
        }

        val subscriptionManager =
            context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        val subscriptions = try {
            subscriptionManager.activeSubscriptionInfoList.orEmpty()
        } catch (error: SecurityException) {
            Log.w(TAG, "active subscriptions denied: ${error.javaClass.simpleName}")
            result.success(
                baseResult(
                    availabilityReason = "security_exception",
                    transportType = currentTransport(),
                ),
            )
            return
        }

        val defaultDataId = SubscriptionManager.getDefaultDataSubscriptionId()
        val selected = subscriptions.firstOrNull { it.subscriptionId == defaultDataId }
            ?: subscriptions.firstOrNull()
        if (selected == null) {
            Log.d(TAG, "capture: api=${Build.VERSION.SDK_INT} subscriptions=0 reason=no_sim")
            result.success(
                baseResult(
                    availabilityReason = "no_sim",
                    transportType = currentTransport(),
                ),
            )
            return
        }

        val rootManager =
            context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val manager = rootManager.createForSubscriptionId(selected.subscriptionId)
        val capture = Capture(
            manager = manager,
            result = result,
            subscriptionCount = subscriptions.size,
            subscriptionSlot = selected.simSlotIndex,
            subscriptionCarrier = selected.carrierName?.toString(),
            isDefaultData = selected.subscriptionId == defaultDataId,
            transportType = currentTransport(),
        )
        activeCapture = capture
        capture.start()
    }

    private fun currentTransport(): String {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities =
            connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return "none"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "other"
        }
    }

    fun dispose() {
        activeCapture?.cancel("disposed")
        activeCapture = null
        channel.setMethodCallHandler(null)
    }

    private inner class Capture(
        private val manager: TelephonyManager,
        private val result: MethodChannel.Result,
        private val subscriptionCount: Int,
        private val subscriptionSlot: Int,
        private val subscriptionCarrier: String?,
        private val isDefaultData: Boolean,
        private val transportType: String,
    ) {
        private val completed = AtomicBoolean(false)
        private var displayInfo: TelephonyDisplayInfo? = null
        private var signalStrength: SignalStrength? = null
        private var serviceState: ServiceState? = null

        private val callback = object :
            TelephonyCallback(),
            TelephonyCallback.DisplayInfoListener,
            TelephonyCallback.SignalStrengthsListener,
            TelephonyCallback.ServiceStateListener {
            override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
                displayInfo = info
                maybeComplete()
            }

            override fun onSignalStrengthsChanged(value: SignalStrength) {
                signalStrength = value
                maybeComplete()
            }

            override fun onServiceStateChanged(value: ServiceState) {
                serviceState = value
                maybeComplete()
            }
        }

        fun start() {
            try {
                manager.registerTelephonyCallback(mainExecutor, callback)
                Log.d(
                    TAG,
                    "capture start: android=${Build.VERSION.RELEASE} api=${Build.VERSION.SDK_INT} " +
                        "subscriptions=$subscriptionCount slot=$subscriptionSlot " +
                        "defaultData=$isDefaultData permission=true",
                )
                mainExecutor.execute {
                    android.os.Handler(context.mainLooper).postDelayed(
                        { complete("timeout") },
                        CALLBACK_TIMEOUT_MS,
                    )
                }
            } catch (error: SecurityException) {
                Log.w(TAG, "register callback denied: ${error.javaClass.simpleName}")
                complete("security_exception")
            } catch (error: RuntimeException) {
                Log.w(TAG, "register callback failed: ${error.javaClass.simpleName}")
                complete("api_error")
            }
        }

        private fun maybeComplete() {
            if (signalStrength != null && displayInfo != null && serviceState != null) {
                complete(null)
            }
        }

        fun cancel(reason: String) = complete(reason)

        private fun complete(forcedReason: String?) {
            if (!completed.compareAndSet(false, true)) return
            try {
                manager.unregisterTelephonyCallback(callback)
                Log.d(TAG, "telephony callback unregistered")
            } catch (_: RuntimeException) {
                Log.d(TAG, "telephony callback already unavailable")
            }
            activeCapture = null

            val service = serviceState
            val inService = service?.state == ServiceState.STATE_IN_SERVICE
            val rawType = try {
                manager.dataNetworkType
            } catch (_: SecurityException) {
                TelephonyManager.NETWORK_TYPE_UNKNOWN
            }
            val overrideType = displayInfo?.overrideNetworkType
                ?: TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NONE
            val technology = mapTechnology(rawType, overrideType)
            val selectedSignal = selectSignal(signalStrength)
            val operator = listOf(
                service?.operatorAlphaLong,
                manager.networkOperatorName,
                subscriptionCarrier,
            ).firstOrNull { !it.isNullOrBlank() }?.trim()
            val reason = forcedReason ?: when {
                !inService -> "no_service"
                operator == null && technology == null && selectedSignal == null -> "not_reported"
                else -> null
            }
            val payload = baseResult(
                availabilityReason = reason,
                transportType = transportType,
            ).toMutableMap().apply {
                put("carrierName", operator)
                put("networkTechnology", technology)
                put("networkTypeRaw", networkTypeName(rawType))
                put("networkTypeRawValue", rawType)
                put("overrideNetworkTypeRaw", overrideTypeName(overrideType))
                put("overrideNetworkTypeRawValue", overrideType)
                put("signalLevel", selectedSignal?.level)
                put("signalPercent", selectedSignal?.level?.times(25))
                put("signalDbm", selectedSignal?.dbm)
                put("signalAsu", selectedSignal?.asuLevel)
                put("signalSource", selectedSignal?.javaClass?.simpleName)
                put("subscriptionSlot", subscriptionSlot)
                put("subscriptionCount", subscriptionCount)
                put("isDefaultDataSubscription", isDefaultData)
                put("isRoaming", service?.roaming)
                put("inService", inService)
            }
            Log.d(
                TAG,
                "capture result: transport=$transportType carrier=${operator != null} " +
                    "raw=${networkTypeName(rawType)} override=${overrideTypeName(overrideType)} " +
                    "technology=$technology level=${selectedSignal?.level} " +
                    "dbm=${selectedSignal?.dbm} source=${selectedSignal?.javaClass?.simpleName} " +
                    "reason=$reason callbackReleased=true",
            )
            result.success(payload)
        }
    }

    private fun selectSignal(value: SignalStrength?): CellSignalStrength? {
        if (value == null) return null
        val valid = value.cellSignalStrengths.filter {
            it.dbm != CellInfo.UNAVAILABLE && it.level in 0..4
        }
        return valid.maxByOrNull { it.level }
    }

    private fun mapTechnology(raw: Int, override: Int): String? {
        if (
            override == TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA ||
            override == TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED
        ) return "5G NSA"
        return when (raw) {
            TelephonyManager.NETWORK_TYPE_NR -> "5G SA"
            TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
            TelephonyManager.NETWORK_TYPE_GPRS,
            TelephonyManager.NETWORK_TYPE_EDGE,
            TelephonyManager.NETWORK_TYPE_GSM,
            TelephonyManager.NETWORK_TYPE_CDMA,
            TelephonyManager.NETWORK_TYPE_1xRTT,
            TelephonyManager.NETWORK_TYPE_IDEN,
            -> "2G"
            TelephonyManager.NETWORK_TYPE_UMTS,
            TelephonyManager.NETWORK_TYPE_EVDO_0,
            TelephonyManager.NETWORK_TYPE_EVDO_A,
            TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA,
            TelephonyManager.NETWORK_TYPE_HSPA,
            TelephonyManager.NETWORK_TYPE_EVDO_B,
            TelephonyManager.NETWORK_TYPE_EHRPD,
            TelephonyManager.NETWORK_TYPE_HSPAP,
            TelephonyManager.NETWORK_TYPE_TD_SCDMA,
            -> "3G"
            TelephonyManager.NETWORK_TYPE_IWLAN -> "Wi-Fi"
            else -> null
        }
    }

    private fun networkTypeName(value: Int): String = when (value) {
        TelephonyManager.NETWORK_TYPE_GPRS -> "GPRS"
        TelephonyManager.NETWORK_TYPE_EDGE -> "EDGE"
        TelephonyManager.NETWORK_TYPE_UMTS -> "UMTS"
        TelephonyManager.NETWORK_TYPE_CDMA -> "CDMA"
        TelephonyManager.NETWORK_TYPE_EVDO_0 -> "EVDO_0"
        TelephonyManager.NETWORK_TYPE_EVDO_A -> "EVDO_A"
        TelephonyManager.NETWORK_TYPE_1xRTT -> "1xRTT"
        TelephonyManager.NETWORK_TYPE_HSDPA -> "HSDPA"
        TelephonyManager.NETWORK_TYPE_HSUPA -> "HSUPA"
        TelephonyManager.NETWORK_TYPE_HSPA -> "HSPA"
        TelephonyManager.NETWORK_TYPE_IDEN -> "IDEN"
        TelephonyManager.NETWORK_TYPE_EVDO_B -> "EVDO_B"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_EHRPD -> "EHRPD"
        TelephonyManager.NETWORK_TYPE_HSPAP -> "HSPAP"
        TelephonyManager.NETWORK_TYPE_GSM -> "GSM"
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "TD_SCDMA"
        TelephonyManager.NETWORK_TYPE_IWLAN -> "IWLAN"
        TelephonyManager.NETWORK_TYPE_NR -> "NR"
        else -> "UNKNOWN"
    }

    private fun overrideTypeName(value: Int): String = when (value) {
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA -> "LTE_CA"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO -> "LTE_ADVANCED_PRO"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA -> "NR_NSA"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED -> "NR_ADVANCED"
        else -> "NONE"
    }

    private fun baseResult(
        availabilityReason: String?,
        transportType: String,
    ): Map<String, Any?> = mapOf(
        "transportType" to transportType,
        "availabilityReason" to availabilityReason,
        "capturedAt" to java.time.Instant.now().toString(),
        "androidApi" to Build.VERSION.SDK_INT,
    )

    companion object {
        private const val CHANNEL_NAME = "com.aquafim.ddr001diag/cellular_telephony"
        private const val TAG = "RvTelephony"
        private const val CALLBACK_TIMEOUT_MS = 3_500L
    }
}
