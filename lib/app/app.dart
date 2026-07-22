import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/app_state.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class DiagnosticApp extends StatelessWidget {
  const DiagnosticApp({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: state,
    child: Builder(
      builder: (context) => MaterialApp.router(
        title: 'DIAGNOSTICO HIDRANTES',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: createRouter(context.read<AppState>()),
      ),
    ),
  );
}
