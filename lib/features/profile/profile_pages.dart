import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/services/update_service.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Perfil',
        subtitle: state.user.role,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(online: state.online),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 31,
                  backgroundColor: AppColors.blue,
                  child: Text(
                    state.user.fullName
                        .split(' ')
                        .map((x) => x[0])
                        .take(2)
                        .join(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.user.fullName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        state.user.role,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      Text(
                        '${state.user.brigadeName} · ${state.user.deviceId}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ESTADÍSTICAS DE HOY',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                SizedBox(height: 18),
                Row(
                  children: [
                    Metric(value: '5', label: 'Completados'),
                    Metric(
                      value: '5',
                      label: 'Pendientes',
                      color: AppColors.orange,
                    ),
                    Metric(
                      value: '2',
                      label: 'Sin sincronizar',
                      color: AppColors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Menu(
                  icon: Icons.sync,
                  title: 'Sincronización',
                  subtitle: '${state.pendingCount} registros pendientes',
                  onTap: () => context.push('/sync'),
                ),
                _Menu(
                  icon: Icons.history,
                  title: 'Historial de actividad',
                  subtitle: '${state.traceBox.length} eventos locales',
                  onTap: () => _message(
                    context,
                    'El historial detallado se incorporará en Etapa 2.',
                  ),
                ),
                _Menu(
                  icon: Icons.lock_outline,
                  title: 'Cambiar contraseña',
                  onTap: () =>
                      _message(context, 'Función no disponible en modo demo.'),
                ),
                _Menu(
                  icon: Icons.menu_book_outlined,
                  title: 'Manual de uso',
                  onTap: () {
                    state.trace('manual_open', 'Abrir manual de uso');
                    context.push('/profile/manual');
                  },
                ),
                _Menu(
                  icon: Icons.system_update_alt,
                  title: 'Revisar actualización',
                  subtitle: state.updateInfo?.status.name,
                  onTap: () {
                    state.trace('update_check', 'Revisar actualización');
                    context.push('/profile/update');
                  },
                ),
                if (state.user.role.toLowerCase().contains('supervisor') ||
                    state.user.role.toLowerCase().contains('admin'))
                  _Menu(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Auditoría técnica local',
                    subtitle: 'Integridad, recuperación y cuarentena',
                    onTap: () => context.push('/profile/integrity'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simular conexión'),
              subtitle: const Text('Solo para demostración'),
              value: state.online,
              onChanged: (_) => state.toggleConnection(),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 52),
              foregroundColor: AppColors.red,
              side: const BorderSide(color: Color(0xFFFFAAAA)),
            ),
            onPressed: () async {
              await state.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 14),
          Center(child: VersionLabel(state.versionLabel)),
        ],
      ),
    );
  }

  static void _message(BuildContext context, String value) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.muted),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 11)),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class ManualPage extends StatelessWidget {
  const ManualPage({super.key});
  @override
  Widget build(BuildContext context) {
    final version = context.watch<AppState>().versionLabel;
    return Scaffold(
      appBar: const AppPageHeader(
        title: 'Manual de uso',
        subtitle: 'Guía rápida',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credenciales de prueba',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Usuario: inspector.demo@ddr001.mx\nContraseña: demo123',
                  style: TextStyle(color: Colors.white, height: 1.7),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final item in const [
            (
              '1. Inicio de sesión',
              'Ingresa con la cuenta demo. La sesión puede recordarse localmente.',
            ),
            (
              '2. Inicio',
              'Consulta asignaciones, avances y registros devueltos.',
            ),
            (
              '3. Lista de hidrantes',
              'Busca, filtra y abre la ficha de un hidrante.',
            ),
            (
              '4. Mapa simulado',
              'Toca un marcador para consultar datos y abrir la ficha.',
            ),
            (
              '5. Sincronización',
              'Ejecuta la simulación sin borrar datos de evidencia reales.',
            ),
            (
              '6. Trabajo offline',
              'Las trazas y la cola demo se conservan localmente.',
            ),
            (
              '7. Estados de reportes',
              'Borrador: información guardada sin finalizar.\nListo: preparación mínima completa.\nEn proceso: inspección activa.\nPausado: detención temporal recuperable.\nSuspendido: detención técnica, operativa o de seguridad.\nFinalizado: reporte cerrado e inmutable.\nCancelado: no continuará.\nRequiere repetición: debe crearse una inspección relacionada.\nPendiente de revisión: requiere supervisión.\nSincronizado: confirmación local simulada hasta contar con backend real.',
            ),
            (
              '8. Términos de captura',
              'RV es REPORTE VISUAL y RF es REPORTE FUNCIONAL. Sin sincronizar indica datos pendientes. No aplica es diferente de No realizada. No verificado indica que no fue posible confirmar Sí o No. Visita sin prueba documenta una visita donde no se ejecutaron pruebas.',
            ),
          ]) ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    item.$2,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Center(child: VersionLabel(version)),
        ],
      ),
    );
  }
}

class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final info = state.updateInfo;
    final color = info?.status == UpdateStatus.required
        ? AppColors.red
        : info?.status == UpdateStatus.optional
        ? AppColors.orange
        : AppColors.green;
    return Scaffold(
      appBar: const AppPageHeader(title: 'Actualizaciones'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: .25),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.science_outlined, color: AppColors.violet),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Modo demostración de actualización',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.violet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<UpdateDemoScenario>(
            key: ValueKey(state.updateDemoScenario),
            initialValue: state.updateDemoScenario,
            decoration: const InputDecoration(labelText: 'Escenario'),
            items: const [
              DropdownMenuItem(
                value: UpdateDemoScenario.current,
                child: Text('Aplicación actualizada'),
              ),
              DropdownMenuItem(
                value: UpdateDemoScenario.optional,
                child: Text('Actualización opcional'),
              ),
              DropdownMenuItem(
                value: UpdateDemoScenario.required,
                child: Text('Actualización obligatoria'),
              ),
              DropdownMenuItem(
                value: UpdateDemoScenario.error,
                child: Text('Error de consulta'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                state.setUpdateScenario(value);
              }
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => state.checkConfiguredManifest(),
            icon: const Icon(Icons.public),
            label: const Text('Comprobar manifiesto configurado'),
          ),
          const SizedBox(height: 12),
          SectionCard(
            child: Column(
              children: [
                Icon(Icons.system_update_alt, size: 54, color: color),
                const SizedBox(height: 15),
                Text(
                  info?.title ?? 'Comprobando...',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Instalada: ${state.versionLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (info != null && info.latestVersion.isNotEmpty)
                  Text(
                    'Disponible: ${info.latestVersion}+${info.buildNumber}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 9),
                Text(
                  info?.message ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                StatusBadge(info?.status.name ?? 'unavailable', color: color),
                if (info != null && info.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Notas: ${info.releaseNotes.join(' · ')}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'No se descargan ni instalan paquetes automáticamente. Una actualización obligatoria permite consultar datos locales y sincronizar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (info?.status == UpdateStatus.optional)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            state.postponeUpdate();
                            context.pop();
                          },
                          child: const Text('Más tarde'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _openDemo(context, state),
                          child: const Text('Actualizar'),
                        ),
                      ),
                    ],
                  ),
                if (info?.status == UpdateStatus.required) ...[
                  FilledButton(
                    onPressed: () => _openDemo(context, state),
                    child: const Text('Actualizar ahora'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/sync'),
                    icon: const Icon(Icons.sync),
                    label: const Text('Abrir sincronización'),
                  ),
                ],
                if (info?.status == UpdateStatus.unavailable)
                  FilledButton.icon(
                    onPressed: () => state.checkUpdates(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _openDemo(BuildContext context, AppState state) async {
    final opened = await state.openUpdate();
    if (context.mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'URL de demostración: no se iniciará ninguna descarga.',
          ),
        ),
      );
    }
  }
}
