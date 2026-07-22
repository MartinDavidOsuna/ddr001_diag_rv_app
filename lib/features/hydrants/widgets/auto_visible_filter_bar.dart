import 'dart:math' as math;

import 'package:flutter/material.dart';

class AutoVisibleFilterBar<T extends Object> extends StatefulWidget {
  const AutoVisibleFilterBar({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    this.isActive = true,
    this.visibilityRequestId,
    this.onVisibilityRequestConsumed,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;
  final bool isActive;
  final String? visibilityRequestId;
  final ValueChanged<String>? onVisibilityRequestConsumed;

  @override
  State<AutoVisibleFilterBar<T>> createState() =>
      _AutoVisibleFilterBarState<T>();
}

class _AutoVisibleFilterBarState<T extends Object>
    extends State<AutoVisibleFilterBar<T>>
    with WidgetsBindingObserver {
  final ScrollController _horizontalController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<T, GlobalKey> _chipKeys = {};
  String? _lastConsumedRequestId;
  bool _callbackScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _synchronizeKeys();
  }

  @override
  void didUpdateWidget(covariant AutoVisibleFilterBar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronizeKeys();
    if (oldWidget.selected != widget.selected ||
        oldWidget.isActive != widget.isActive ||
        oldWidget.visibilityRequestId != widget.visibilityRequestId) {
      _scheduleVisibility(consumeRequest: widget.visibilityRequestId != null);
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleVisibility(consumeRequest: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _horizontalController.dispose();
    super.dispose();
  }

  void _synchronizeKeys() {
    for (final value in widget.values) {
      _chipKeys.putIfAbsent(value, GlobalKey.new);
    }
    _chipKeys.removeWhere((value, _) => !widget.values.contains(value));
  }

  void _scheduleVisibility({required bool consumeRequest, int attempt = 0}) {
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _callbackScheduled = false;
      if (!mounted) return;
      final succeeded = await _makeSelectedVisible();
      if (!mounted) return;
      if (!succeeded) {
        if (attempt < 4) {
          _scheduleVisibility(
            consumeRequest: consumeRequest,
            attempt: attempt + 1,
          );
        }
        return;
      }
      if (!consumeRequest) return;
      final requestId = widget.visibilityRequestId;
      if (requestId == null || requestId == _lastConsumedRequestId) return;
      _lastConsumedRequestId = requestId;
      widget.onVisibilityRequestConsumed?.call(requestId);
    });
  }

  Future<bool> _makeSelectedVisible() async {
    if (!widget.isActive || !_horizontalController.hasClients) return false;
    final chipContext = _chipKeys[widget.selected]?.currentContext;
    final viewportContext = _viewportKey.currentContext;
    if (chipContext == null || viewportContext == null) return false;
    final chipBox = chipContext.findRenderObject();
    final viewportBox = viewportContext.findRenderObject();
    if (chipBox is! RenderBox ||
        viewportBox is! RenderBox ||
        !chipBox.attached ||
        !viewportBox.attached) {
      return false;
    }

    final chipLeft = chipBox
        .localToGlobal(Offset.zero, ancestor: viewportBox)
        .dx;
    final chipRight = chipLeft + chipBox.size.width;
    final viewportWidth = viewportBox.size.width;
    const margin = 12.0;
    final fullyVisible =
        chipLeft >= margin && chipRight <= viewportWidth - margin;
    if (fullyVisible) return true;

    final chipCenter = (chipLeft + chipRight) / 2;
    final delta = chipCenter - viewportWidth / 2;
    final position = _horizontalController.position;
    final target = math.max(
      position.minScrollExtent,
      math.min(position.maxScrollExtent, position.pixels + delta),
    );
    await _horizontalController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    return mounted && _horizontalController.hasClients;
  }

  @override
  Widget build(BuildContext context) {
    final requestId = widget.visibilityRequestId;
    if (requestId != null && requestId != _lastConsumedRequestId) {
      _scheduleVisibility(consumeRequest: true);
    }
    return SizedBox(
      key: _viewportKey,
      height: 42,
      child: ListView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final value in widget.values)
            Padding(
              key: _chipKeys[value],
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(widget.labelFor(value)),
                selected: widget.selected == value,
                onSelected: (_) {
                  widget.onSelected(value);
                  _scheduleVisibility(consumeRequest: false);
                },
              ),
            ),
        ],
      ),
    );
  }
}
