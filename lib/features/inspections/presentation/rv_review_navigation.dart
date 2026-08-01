import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/navigation_keys.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';

enum RvHorizontalNavigationIntent { none, next, previous }

class RvGestureNavigationPolicy {
  const RvGestureNavigationPolicy({
    this.minimumDistance = 72,
    this.minimumVelocity = 280,
  });

  final double minimumDistance;
  final double minimumVelocity;

  RvHorizontalNavigationIntent resolve({
    required double horizontalDistance,
    required double verticalDistance,
    required double horizontalVelocity,
  }) {
    if (horizontalDistance.abs() < minimumDistance &&
        horizontalVelocity.abs() < minimumVelocity) {
      return RvHorizontalNavigationIntent.none;
    }
    if (horizontalDistance.abs() <= verticalDistance.abs() * 1.25) {
      return RvHorizontalNavigationIntent.none;
    }
    final direction = horizontalDistance.abs() >= minimumDistance
        ? horizontalDistance
        : horizontalVelocity;
    return direction < 0
        ? RvHorizontalNavigationIntent.next
        : RvHorizontalNavigationIntent.previous;
  }
}

class RvSubmissionCompletionGate {
  bool _consumed = false;

  bool consumeIfComplete(RvDraft draft) {
    if (_consumed ||
        draft.localStatus != RvLocalStatus.submitted ||
        draft.remoteStatus != 'submitted') {
      return false;
    }
    _consumed = true;
    return true;
  }
}

class RvSwipeNavigationDetector extends StatefulWidget {
  const RvSwipeNavigationDetector({
    required this.child,
    required this.onNext,
    required this.onPrevious,
    this.enabled = true,
    this.policy = const RvGestureNavigationPolicy(),
    super.key,
  });

  final Widget child;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final bool enabled;
  final RvGestureNavigationPolicy policy;

  @override
  State<RvSwipeNavigationDetector> createState() =>
      _RvSwipeNavigationDetectorState();
}

class _RvSwipeNavigationDetectorState extends State<RvSwipeNavigationDetector> {
  double _horizontalDistance = 0;
  double _verticalDistance = 0;
  bool _transitioning = false;

  Future<void> _finish(DragEndDetails details) async {
    if (!widget.enabled || _transitioning) return;
    final intent = widget.policy.resolve(
      horizontalDistance: _horizontalDistance,
      verticalDistance: _verticalDistance,
      horizontalVelocity: details.primaryVelocity ?? 0,
    );
    _resetDistance();
    if (intent == RvHorizontalNavigationIntent.none) return;
    _transitioning = true;
    try {
      if (intent == RvHorizontalNavigationIntent.next) {
        await widget.onNext();
      } else {
        await widget.onPrevious();
      }
    } finally {
      _transitioning = false;
    }
  }

  void _resetDistance() {
    _horizontalDistance = 0;
    _verticalDistance = 0;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _resetDistance() : null,
    onPointerMove: widget.enabled
        ? (event) {
            _horizontalDistance += event.delta.dx;
            _verticalDistance += event.delta.dy;
          }
        : null,
    onPointerCancel: widget.enabled ? (_) => _resetDistance() : null,
    child: GestureDetector(
      key: const ValueKey('rv-horizontal-navigation'),
      behavior: HitTestBehavior.translucent,
      onHorizontalDragCancel: widget.enabled ? _resetDistance : null,
      onHorizontalDragEnd: widget.enabled ? _finish : null,
      child: widget.child,
    ),
  );
}

class RvReviewNavigation {
  const RvReviewNavigation._();

  static Future<bool> requestExitReview(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Salir de la revisión?'),
          content: const Text(
            'Tus avances guardados se conservarán y podrás continuar después.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Continuar revisión'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salir'),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> showSubmissionSuccessAndReturnHome(
    BuildContext context,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Inspección enviada'),
          content: const Text(
            'La inspección se sincronizó y envió correctamente.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    hydrantsNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (context.mounted) context.go('/home');
  }

  static Future<void> showConflictAndReturnHome(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Conflicto de revisión'),
          content: const Text(
            'Otro reporte se confirmó primero. Tu revisión, respuestas y '
            'fotografías quedaron guardadas para su resolución.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    hydrantsNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (context.mounted) context.go('/home');
  }
}
