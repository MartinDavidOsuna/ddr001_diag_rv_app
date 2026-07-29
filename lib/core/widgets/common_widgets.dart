import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../network/connectivity_monitor.dart';
import 'app_brand_logo.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {this.color = AppColors.brightBlue, super.key});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    required this.online,
    this.state,
    this.pending = false,
    super.key,
  });
  final bool online;
  final NetworkAvailabilityState? state;
  final bool pending;
  @override
  Widget build(BuildContext context) {
    final label = pending
        ? 'Pendiente de sincronizar'
        : switch (state) {
            NetworkAvailabilityState.noNetwork => 'Sin conexión',
            NetworkAvailabilityState.internetAvailable => 'Internet disponible',
            NetworkAvailabilityState.apiUnavailable => 'Servidor no disponible',
            NetworkAvailabilityState.apiAvailable => 'API disponible',
            NetworkAvailabilityState.checking => 'Comprobando',
            null => online ? 'En línea' : 'Sin conexión',
          };
    final color = pending
        ? AppColors.orange
        : state == NetworkAvailabilityState.apiAvailable ||
              (state == null && online)
        ? AppColors.green
        : state == NetworkAvailabilityState.noNetwork
        ? AppColors.red
        : AppColors.orange;
    return StatusBadge(label, color: color);
  }
}

class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    super.key,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 56 : 62);
  @override
  Widget build(BuildContext context) => AppBar(
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    title: Row(
      children: [
        const AppBrandLogo(
          variant: AppBrandLogoVariant.symbol,
          width: 30,
          height: 30,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
    actions: actions,
  );
}

class Metric extends StatelessWidget {
  const Metric({
    required this.value,
    required this.label,
    this.color = AppColors.ink,
    this.onTap,
    super.key,
  });
  final String value, label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

class VersionLabel extends StatelessWidget {
  const VersionLabel(this.version, {super.key});
  final String version;
  @override
  Widget build(BuildContext context) => Text(
    'Versión $version',
    style: const TextStyle(fontSize: 11, color: AppColors.muted),
  );
}
