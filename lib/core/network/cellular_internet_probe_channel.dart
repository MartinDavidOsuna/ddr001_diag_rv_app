import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/network/cellular_network_diagnostic.dart';
import 'cellular_probe_configuration.dart';

typedef CellularProbeProgressCallback = void Function(String stage);

class CellularInternetProbeChannel {
  CellularInternetProbeChannel({
    MethodChannel? channel,
    bool Function()? isAndroid,
    String Function()? platformName,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _isAndroid = isAndroid ?? (() => Platform.isAndroid),
       _platformName = platformName ?? (() => Platform.operatingSystem) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final CellularInternetProbeChannel instance =
      CellularInternetProbeChannel();
  static const _channelName =
      'com.aquafim.ddr001diag/cellular_internet_probe';

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final String Function() _platformName;

  final Map<String, CellularProbeProgressCallback> _progressCallbacks = {};

  Future<CellularInternetProbeResult> start({
    required String probeId,
    required CellularProbeConfiguration configuration,
    CellularProbeProgressCallback? onProgress,
  }) async {
    if (!_isAndroid()) {
      return CellularInternetProbeResult.platformRestricted(
        methodVersion: configuration.methodVersion,
        platform: _platformName(),
      );
    }
    if (onProgress != null) _progressCallbacks[probeId] = onProgress;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'startProbe',
        configuration.toChannelArguments(probeId),
      );
      return CellularInternetProbeResult.fromJson(raw ?? const {});
    } on PlatformException catch (error) {
      return CellularInternetProbeResult.platformError(
        methodVersion: configuration.methodVersion,
        platform: 'android',
        code: error.code,
        message: error.message,
      );
    } finally {
      _progressCallbacks.remove(probeId);
    }
  }

  Future<void> cancel(String probeId) async {
    _progressCallbacks.remove(probeId);
    if (!_isAndroid()) return;
    try {
      await _channel.invokeMethod<void>('cancelProbe', {'probeId': probeId});
    } on PlatformException {
      // La operación nativa puede haber finalizado entre el toque y la llamada.
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'probeProgress') return;
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final probeId = arguments['probeId'] as String?;
    final stage = arguments['stage'] as String?;
    if (probeId != null && stage != null) {
      _progressCallbacks[probeId]?.call(stage);
    }
  }
}
