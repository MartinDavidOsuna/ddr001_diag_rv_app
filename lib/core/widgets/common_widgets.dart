import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

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
  const ConnectionBadge({required this.online, super.key});
  final bool online;
  @override
  Widget build(BuildContext context) => StatusBadge(
    online ? 'En línea' : 'Sin conexión',
    color: online ? AppColors.green : AppColors.orange,
  );
}

class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.actions,
    super.key,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 56 : 62);
  @override
  Widget build(BuildContext context) => AppBar(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        if (subtitle != null)
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
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
