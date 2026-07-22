import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';

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
  final email = TextEditingController(text: 'inspector.demo@ddr001.mx');
  final password = TextEditingController(text: 'demo123');
  bool remember = true, obscure = true;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final ok = await context.read<AppState>().login(
      email.text,
      password.text,
      remember: remember,
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      context.go('/home');
    } else {
      setState(() => error = 'Credenciales demo incorrectas');
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
                              'Contraseña',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 7),
                            TextField(
                              controller: password,
                              obscureText: obscure,
                              onSubmitted: (_) => submit(),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: remember,
                                  onChanged: (v) =>
                                      setState(() => remember = v ?? false),
                                ),
                                const Text('Recordar sesión'),
                                const Spacer(),
                                TextButton(
                                  onPressed: () =>
                                      message('Recuperación simulada'),
                                  child: const Text('Recuperar'),
                                ),
                              ],
                            ),
                            if (error != null)
                              Text(
                                error!,
                                style: const TextStyle(color: AppColors.red),
                              ),
                            FilledButton(
                              onPressed: submit,
                              child: const Text('Iniciar sesión'),
                            ),
                            TextButton(
                              onPressed: () => message(
                                'La creación de cuentas estará disponible posteriormente.',
                              ),
                              child: const Text('Crear cuenta demo'),
                            ),
                            const Text(
                              'Acceso demo local, sin autenticación remota.',
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
