import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/app_state.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class DiagnosticApp extends StatefulWidget {
  const DiagnosticApp({required this.state, super.key});

  final AppState state;

  @override
  State<DiagnosticApp> createState() => _DiagnosticAppState();
}

class _DiagnosticAppState extends State<DiagnosticApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.state.recheckConnectivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: widget.state,
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
