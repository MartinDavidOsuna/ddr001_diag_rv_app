import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
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
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.blue,
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.water_drop_outlined, size: 72, color: Colors.white),
            SizedBox(height: 22),
            Text(
              'DIAGNOSTICO HIDRANTES',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Distrito de Riego 001',
              style: TextStyle(color: Color(0xFFC9D5FF), fontSize: 16),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(color: Colors.white),
          ],
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
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    crew.dispose();
    super.dispose();
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
                    const Icon(
                      Icons.water_drop_outlined,
                      color: Colors.white,
                      size: 60,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'DIAGNOSTICO HIDRANTES',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Distrito de Riego 001',
                      style: TextStyle(color: Color(0xFFC9D5FF), fontSize: 15),
                    ),
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
                            if (error != null)
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
                    ConnectionBadge(online: state.online),
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
