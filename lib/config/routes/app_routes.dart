import 'package:go_router/go_router.dart';
import '../../features/billing/presentation/pages/home_page.dart';
import '../../features/product/presentation/pages/product_list_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/shop/presentation/pages/shop_details_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/billing/presentation/pages/scanner_page.dart';
import '../../features/billing/presentation/pages/checkout_page.dart';
import '../../features/billing/presentation/pages/return_page.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/presentation/pages/user_management_page.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/data_transfer/presentation/pages/import_export_page.dart';
import '../../features/history/presentation/pages/history_page.dart';
import '../../features/product/domain/entities/product.dart';

GoRouter buildRouter() {
  final auth = AuthService();

  bool adminOnly(String path) =>
      path == '/products' ||
      path.startsWith('/products/') ||
      path == '/shop' ||
      path == '/import-export';

  return GoRouter(
    initialLocation: auth.isLoggedIn ? '/' : '/login',
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final isLogin = state.matchedLocation == '/login';

      if (!loggedIn && !isLogin) return '/login';
      if (loggedIn && isLogin) return '/';

      if (loggedIn && adminOnly(state.matchedLocation) && !auth.isAdmin) {
        return '/';
      }

      if (loggedIn &&
          state.matchedLocation == '/users' &&
          !auth.isAdmin) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const AuthPage()),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
        routes: [
          GoRoute(
              path: 'scanner',
              builder: (context, state) => const ScannerPage()),
          GoRoute(
              path: 'checkout',
              builder: (context, state) => const CheckoutPage()),
          GoRoute(
              path: 'returns',
              builder: (context, state) => const ReturnPage()),
        ],
      ),
      GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage()),
      GoRoute(
          path: '/import-export',
          builder: (context, state) => const ImportExportPage()),
      GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryPage()),
      GoRoute(
        path: '/users',
        builder: (context, state) => const UserManagementPage(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductListPage(),
        routes: [
          GoRoute(
              path: 'add',
              builder: (context, state) => const AddProductPage()),
          GoRoute(
            path: 'edit/:id',
            builder: (context, state) {
              final product = state.extra as Product?;
              if (product == null) return const ProductListPage();
              return EditProductPage(product: product);
            },
          ),
        ],
      ),
      GoRoute(
          path: '/shop',
          builder: (context, state) => const ShopDetailsPage()),
    ],
  );
}
