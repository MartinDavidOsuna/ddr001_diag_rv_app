import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class BranchRootPopScope extends StatelessWidget {
  const BranchRootPopScope({
    required this.index,
    required this.child,
    super.key,
  });
  final int index;
  final Widget child;

  Future<void> _back(BuildContext context) async {
    if (index > 0) {
      context.go(['/home', '/hydrants', '/map', '/profile'][index - 1]);
      return;
    }
    final exit =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Salir de la aplicación?'),
            content: const Text(
              'Tus borradores, fotografías y datos locales permanecerán guardados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salir'),
              ),
            ],
          ),
        ) ??
        false;
    if (exit) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        _back(context);
      }
    },
    child: child,
  );
}
