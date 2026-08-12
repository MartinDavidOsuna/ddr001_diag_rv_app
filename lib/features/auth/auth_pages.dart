import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/app_brand_logo.dart';
import '../../core/widgets/common_widgets.dart';
import 'data/field_session_models.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) {
        context.go(context.read<AppState>().authenticated ? '/home' : '/login');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.blue,
    body: SafeArea(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBrandLogo(
                variant: AppBrandLogoVariant.splash,
                width: constraints.maxWidth.clamp(180, 380).toDouble(),
                height: 150,
                borderRadius: BorderRadius.circular(AppTheme.cardCornerRadius),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final crew = TextEditingController();
  bool submitting = false;
  bool revokingSession = false;
  String? error;
  String? takeoverSuccess;
  Timer? _successTimer;
  @override
  void dispose() {
    _successTimer?.cancel();
    name.dispose();
    email.dispose();
    phone.dispose();
    crew.dispose();
    super.dispose();
  }

  Future<void> confirmSessionTakeover() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión activa'),
        content: const Text(
          'Tu usuario tiene una sesión abierta en otro dispositivo. ¿Estás seguro de que deseas cerrar esa sesión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          StatefulBuilder(
            builder: (context, setModalState) => FilledButton(
              onPressed: revokingSession
                  ? null
                  : () async {
                      setModalState(() => revokingSession = true);
                      final failure = await context
                          .read<AppState>()
                          .revokeExistingFieldSession();
                      if (!mounted || !dialogContext.mounted) return;
                      setModalState(() => revokingSession = false);
                      if (failure == null) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        Navigator.pop(dialogContext, false);
                        setState(() => error = failure);
                      }
                    },
              child: revokingSession
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _successTimer?.cancel();
    setState(() {
      error = null;
      takeoverSuccess =
          'La sesión del otro dispositivo se cerró correctamente.';
    });
    _successTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => takeoverSuccess = null);
    });
  }

  Future<void> submit() async {
    if (submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    final failure = await context.read<AppState>().startFieldSession(
      FieldRegistration(
        name: name.text,
        email: email.text,
        phone: phone.text,
        crew: crew.text,
      ),
    );
    if (!mounted) return;
    setState(() => submitting = false);
    if (failure == null) {
      context.go('/home');
    } else {
      setState(() => error = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.blue, AppColors.navy],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    const LoginBrandHeader(),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Nombre completo',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: name,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.person_outline),
                                hintText: 'Nombre y apellidos',
                              ),
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              'Correo electrónico',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.mail_outline),
                                hintText: 'usuario@ejemplo.com',
                              ),
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              'Teléfono',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: phone,
                              keyboardType: TextInputType.phone,
                              maxLength: 10,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.phone_outlined),
                                hintText: '10 dígitos',
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Cuadrilla',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: crew,
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) => submit(),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.groups_outlined),
                                hintText: 'Ejemplo: CUADRILLA NORTE 1',
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (takeoverSuccess != null)
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  takeoverSuccess!,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (error != null &&
                                state.pendingSessionTakeoverToken != null)
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Tu usuario ya está activo en otro dispositivo. ¿Deseas cerrar esa sesión? ',
                                    style: TextStyle(color: AppColors.red),
                                  ),
                                  TextButton(
                                    onPressed: confirmSessionTakeover,
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(44, 44),
                                    ),
                                    child: const Text('Presiona aquí'),
                                  ),
                                ],
                              )
                            else if (error != null)
                              Text(
                                error!,
                                style: const TextStyle(color: AppColors.red),
                              ),
                            FilledButton(
                              onPressed: submitting ? null : submit,
                              child: submitting
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Iniciar sesión de campo'),
                            ),
                            const Text(
                              'La sesión se protege en el almacenamiento seguro del dispositivo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ConnectionBadge(
                      online: state.online,
                      state: state.connectivityState,
                      transport: state.connectivityMonitor?.transport,
                    ),
                    const SizedBox(height: 12),
                    VersionLabel(state.versionLabel),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginBrandHeader extends StatelessWidget {
  const LoginBrandHeader({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 300;
      return AppBrandLogo(
        variant: compact
            ? AppBrandLogoVariant.symbol
            : AppBrandLogoVariant.horizontal,
        width: compact ? 92 : constraints.maxWidth.clamp(220, 340).toDouble(),
        height: compact ? 92 : 108,
        borderRadius: BorderRadius.circular(AppTheme.cardCornerRadius),
      );
    },
  );
}
