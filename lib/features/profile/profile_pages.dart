import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../home/rv_work_dashboard.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = state.profileTodayStats;
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Perfil',
        subtitle: state.user.role,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(
              online: state.online,
              state: state.connectivityState,
              transport: state.connectivityMonitor?.transport,
            ),
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
                        .split(RegExp(r'\s+'))
                        .where((value) => value.isNotEmpty)
                        .map((value) => value[0])
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
                        state.user.brigadeName,
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
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESTADÍSTICAS ACTUALES',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _StatMetric(
                      value: state.profileStatsLoading
                          ? '—'
                          : '${stats.submitted}',
                      label: 'Enviados',
                      color: AppColors.green,
                      onTap: () =>
                          _openWorkGroup(context, RvWorkGroup.submitted),
                    ),
                    _StatMetric(
                      value: state.profileStatsLoading
                          ? '—'
                          : '${stats.pending}',
                      label: 'Pendientes',
                      color: AppColors.orange,
                      onTap: () =>
                          _openWorkGroup(context, RvWorkGroup.inProgress),
                    ),
                    _StatMetric(
                      value: state.profileStatsLoading
                          ? '—'
                          : '${stats.unsynced}',
                      label: 'Sin sincronizar',
                      color: AppColors.red,
                      onTap: () =>
                          _openWorkGroup(context, RvWorkGroup.pendingSync),
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
                  subtitle: '${stats.unsynced} inspecciones pendientes',
                  onTap: () => context.push('/sync'),
                ),
                _Menu(
                  icon: Icons.menu_book_outlined,
                  title: 'Manual de uso',
                  onTap: () {
                    state.trace('manual_open', 'Abrir manual de uso');
                    context.push('/profile/manual');
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
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 52),
              foregroundColor: AppColors.red,
              side: const BorderSide(color: Color(0xFFFFAAAA)),
            ),
            onPressed: () async {
              final closed = await state.logout();
              if (context.mounted && closed) {
                context.go('/login');
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Sin conexión. El cierre de sesión quedó pendiente.',
                    ),
                  ),
                );
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

  static void _openWorkGroup(BuildContext context, RvWorkGroup group) =>
      context.go('/hydrants?workGroup=${group.name}');
}

class _StatMetric extends StatelessWidget {
  const _StatMetric({
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String value;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
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

  static const sections = <(String, String)>[
    (
      '1. Inicio de sesión',
      'Ingresa con las credenciales autorizadas y no compartas tu contraseña. '
          'Cada sesión mantiene separados los borradores y operaciones de su usuario. '
          'Cierra sesión desde Perfil cuando termines.',
    ),
    (
      '2. Hidrantes asignados',
      'Consulta, busca y filtra los hidrantes autorizados. Un hidrante es el '
          'activo físico; una inspección registra su revisión y un borrador es '
          'una inspección todavía editable.',
    ),
    (
      '3. Crear inspección',
      'Selecciona un hidrante, inicia la revisión visual y completa sus '
          'secciones. Los avances se guardan como borrador y puedes continuar '
          'posteriormente.',
    ),
    (
      '4. Respuestas',
      'Completa los selectores y campos obligatorios. Registra observaciones, '
          'marcas, diámetros, condiciones y componentes según lo observado.',
    ),
    (
      '5. Fotografías',
      'Toma una fotografía o selecciónala desde la galería, revísala antes de '
          'continuar y elimina únicamente evidencia incorrecta. Sin conexión, '
          'las fotografías permanecen pendientes hasta sincronizar.',
    ),
    (
      '6. Válvulas parcelarias — paso 8',
      'Selecciona la configuración y cantidad de válvulas. Completa la marca, '
          'diámetro y componentes de cada una. Usa “Otro” cuando la '
          'configuración o medida no esté disponible y revisa los datos.',
    ),
    (
      '7. Resumen',
      'Revisa pendientes y advertencias. Toca un pendiente para ir al campo, '
          'corrígelo y utiliza “Volver al resumen” antes de validar el envío.',
    ),
    (
      '8. Trabajo sin conexión',
      'Puedes capturar respuestas, válvulas y fotografías sin red. La '
          'información queda guardada para el usuario activo y muestra estado '
          'pendiente. Recupera la conexión para sincronizar; evita cerrar la '
          'sesión mientras exista trabajo offline.',
    ),
    (
      '9. Sincronización',
      'Pendiente de sincronizar significa que aún existe información local. '
          'Sincronizando indica una operación activa; Sincronizado confirma la '
          'respuesta remota; Error requiere revisar la causa y reintentar.',
    ),
    (
      '10. Envío',
      'Guardar conserva el borrador; sincronizar transfiere sus elementos; '
          'enviar cierra la inspección tras confirmación. Una inspección enviada '
          'queda bloqueada para edición normal.',
    ),
    (
      '11. Perfil',
      'Consulta tu nombre, rol, cuadrilla, estadísticas actuales, versión, '
          'manual y cierre de sesión. Las estadísticas pertenecen únicamente '
          'a la sesión activa.',
    ),
    (
      '12. Solución de problemas',
      'Sin conexión: continúa offline. Cámara sin permiso: habilítalo en el '
          'sistema. Fotografía rechazada: revisa el archivo. Error de '
          'sincronización: conserva el borrador y reintenta. Sesión vencida: '
          'vuelve a autenticarte. Si la aplicación se cierra, ábrela de nuevo. '
          'Si faltan datos autorizados, contacta a soporte.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final version = context.watch<AppState>().versionLabel;
    return Scaffold(
      appBar: const AppPageHeader(
        title: 'Manual de uso',
        subtitle: 'Guía de operación',
      ),
      body: ListView(
        key: const ValueKey('manual-scroll-view'),
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in sections) ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    section.$2,
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
