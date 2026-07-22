import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../features/auth/auth_pages.dart';
import '../../features/home/home_page.dart';
import '../../features/hydrants/hydrant_pages.dart';
import '../../features/visual_report/presentation/visual_report_page.dart';
import '../../features/hydrants/new_survey_page.dart';
import '../../features/hydrants/photo_gallery_page.dart';
import '../../features/functional/functional_inspection_page.dart';
import '../../features/map/map_page.dart';
import '../../features/profile/profile_pages.dart';
import '../../features/shell/main_shell.dart';
import '../../features/sync/sync_page.dart';
import '../../features/diagnostics/local_integrity_page.dart';
import 'branch_root_pop_scope.dart';
import 'navigation_keys.dart';

GoRouter createRouter(AppState state) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  refreshListenable: state,
  redirect: (context, route) {
    if (route.matchedLocation == '/' || route.matchedLocation == '/login') {
      return null;
    }
    if (!state.authenticated) {
      return '/login';
    }
    final segments = route.uri.pathSegments;
    if (segments.length >= 2 &&
        segments.first == 'hydrants' &&
        segments[1] != 'new' &&
        !state.hydrants.any((item) => item.id == segments[1])) {
      return '/hydrants';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashPage()),
    GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: homeNavigatorKey,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) =>
                  const BranchRootPopScope(index: 0, child: HomePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: hydrantsNavigatorKey,
          routes: [
            GoRoute(
              path: '/hydrants',
              builder: (_, _) =>
                  const BranchRootPopScope(index: 1, child: HydrantsPage()),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (_, _) => state.editingRestricted
                      ? const PlaceholderPage(
                          title: 'Actualización requerida',
                          message:
                              'No puedes crear levantamientos nuevos. Puedes consultar y sincronizar datos.',
                        )
                      : const NewSurveyPage(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (_, route) =>
                      HydrantDetailPage(id: route.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'inspection/:type',
                      builder: (_, route) => route.pathParameters['type'] == 'b'
                          ? FunctionalInspectionPage(
                              hydrantId: route.pathParameters['id']!,
                            )
                          : VisualReportPage(
                              hydrantId: route.pathParameters['id']!,
                              type: route.pathParameters['type']!,
                            ),
                    ),
                    GoRoute(
                      path: 'gallery',
                      builder: (_, route) => PhotoGalleryPage(
                        hydrantId: route.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: mapNavigatorKey,
          routes: [
            GoRoute(
              path: '/map',
              builder: (_, _) =>
                  const BranchRootPopScope(index: 2, child: MapPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: profileNavigatorKey,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) =>
                  const BranchRootPopScope(index: 3, child: ProfilePage()),
              routes: [
                GoRoute(path: 'manual', builder: (_, _) => const ManualPage()),
                GoRoute(path: 'update', builder: (_, _) => const UpdatePage()),
                GoRoute(
                  path: 'integrity',
                  builder: (_, _) => const LocalIntegrityPage(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/sync',
      builder: (_, route) => SyncPage(
        returnLocation: route.uri.queryParameters['return'] ?? '/home',
      ),
    ),
  ],
);
