import 'package:go_router/go_router.dart';
import '../../features/billing/presentation/pages/home_page.dart';
import '../../features/product/presentation/pages/product_list_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/shop/presentation/pages/shop_details_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/billing/presentation/pages/scanner_page.dart';
import '../../features/billing/presentation/pages/checkout_page.dart';
import '../../features/auth/presentation/pages/auth_page.dart';
import '../../features/auth/data/auth_service.dart';
import '../../features/data_transfer/presentation/pages/import_export_page.dart';
import '../../features/product/domain/entities/product.dart';

GoRouter buildRouter() {
  final auth = AuthService();
  return GoRouter(
  initialLocation: auth.isLoggedIn ? '/' : '/login',
  redirect: (context, state) {
    final loggedIn = auth.isLoggedIn;
    final isLogin = state.matchedLocation == '/login';
    if (!loggedIn && !isLogin) return '/login';
    if (loggedIn && isLogin) return '/';
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
          builder: (context, state) => const ScannerPage(),
        ),
        GoRoute(
          path: 'checkout',
          builder: (context, state) => const CheckoutPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(path: '/import-export', builder: (context, state) => const ImportExportPage()),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductListPage(),
      routes: [
        GoRoute(
          path: 'add',
          builder: (context, state) => const AddProductPage(),
        ),
        GoRoute(
          path: 'edit/:id',
          builder: (context, state) {
            final product = state.extra as Product?;
            if (product == null) {
              // If we land here without extra (e.g. deep link), go back to products for now.
              return const ProductListPage();
            }
            return EditProductPage(product: product);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/shop',
      builder: (context, state) => const ShopDetailsPage(),
    ),
  ],
  );
}
