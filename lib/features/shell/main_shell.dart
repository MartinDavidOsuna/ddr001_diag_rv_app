import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_state.dart';

class MainShell extends StatefulWidget {
  const MainShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  bool navigating = false;
  double? dragStartX;
  void navigate(int index) {
    if (navigating || index == widget.navigationShell.currentIndex) return;
    navigating = true;
    widget.navigationShell.goBranch(index, initialLocation: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => navigating = false);
  }

  void swipe(DragEndDetails details) {
    final start = dragStartX;
    dragStartX = null;
    final width = MediaQuery.sizeOf(context).width;
    if (start == null || start < 24 || start > width - 24) return;
    final velocity = details.primaryVelocity ?? 0;
    final current = widget.navigationShell.currentIndex;
    if (velocity < -350 && current < 3) navigate(current + 1);
    if (velocity > 350 && current > 0) navigate(current - 1);
  }

  @override
  Widget build(BuildContext context) {
    final sessionOffline = context.watch<AppState>().sessionOffline;
    final path = GoRouterState.of(context).uri.path;
    final isBranchRoot = const {
      '/home',
      '/hydrants',
      '/map',
      '/profile',
    }.contains(path);
    return Scaffold(
      body: Column(
        children: [
          if (sessionOffline)
            const Material(
              color: Color(0xFFFFE5A8),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Sesión sin verificar — modo sin conexión',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: isBranchRoot
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (d) =>
                        dragStartX = d.globalPosition.dx,
                    onHorizontalDragEnd: swipe,
                    child: widget.navigationShell,
                  )
                : widget.navigationShell,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: navigate,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Hidrantes',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
