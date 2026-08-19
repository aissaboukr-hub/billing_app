import 'package:billing_app/core/error/failure.dart';
import 'package:billing_app/features/billing/domain/entities/cart_item.dart';
import 'package:billing_app/features/billing/presentation/bloc/billing_bloc.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/repositories/product_repository.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

/// Minimal in-memory fake so bloc tests don't touch Hive or platform
/// channels: only [getProductByBarcode] is exercised by BillingBloc.
class FakeProductRepository implements ProductRepository {
  FakeProductRepository(this.products);

  final List<Product> products;

  @override
  Future<Either<Failure, Product>> getProductByBarcode(String barcode) async {
    final match = products.where((p) => p.barcode == barcode).firstOrNull;
    if (match == null) {
      return Left(CacheFailure('Produit introuvable'));
    }
    return Right(match);
  }

  @override
  Future<Either<Failure, List<Product>>> getProducts() async =>
      Right(products);

  @override
  Future<Either<Failure, void>> addProduct(Product product) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> updateProduct(Product product) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> deleteProduct(String id) async =>
      const Right(null);
}

void main() {
  const cola = Product(
    id: '1',
    name: 'Cola 33cl',
    barcode: '1111',
    price: 80,
  );
  const chips = Product(
    id: '2',
    name: 'Chips',
    barcode: '2222',
    price: 150,
  );

  BillingBloc buildBloc() => BillingBloc(
        getProductByBarcodeUseCase:
            GetProductByBarcodeUseCase(FakeProductRepository([cola, chips])),
      );

  group('BillingBloc', () {
    blocTest<BillingBloc, BillingState>(
      'scanning a known barcode adds it to the cart',
      build: buildBloc,
      act: (bloc) => bloc.add(const ScanBarcodeEvent('1111')),
      expect: () => [
        isA<BillingState>()
            .having((s) => s.cartItems.length, 'cartItems.length', 1)
            .having((s) => s.cartItems.first.product, 'product', cola)
            .having((s) => s.cartItems.first.quantity, 'quantity', 1),
      ],
    );

    blocTest<BillingBloc, BillingState>(
      'scanning the same barcode twice increments quantity instead of duplicating',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ScanBarcodeEvent('1111'))
        ..add(const ScanBarcodeEvent('1111')),
      expect: () => [
        isA<BillingState>().having((s) => s.cartItems.length, 'len', 1),
        isA<BillingState>()
            .having((s) => s.cartItems.length, 'len', 1)
            .having((s) => s.cartItems.first.quantity, 'quantity', 2),
      ],
    );

    blocTest<BillingBloc, BillingState>(
      'scanning an unknown barcode sets an error and does not touch the cart',
      build: buildBloc,
      act: (bloc) => bloc.add(const ScanBarcodeEvent('9999')),
      expect: () => [
        isA<BillingState>()
            .having((s) => s.cartItems, 'cartItems', isEmpty)
            .having((s) => s.error, 'error', contains('9999')),
      ],
    );

    blocTest<BillingBloc, BillingState>(
      'updating quantity to zero removes the item',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ScanBarcodeEvent('1111'))
        ..add(const UpdateQuantityEvent('1', 0)),
      skip: 1,
      expect: () => [
        isA<BillingState>().having((s) => s.cartItems, 'cartItems', isEmpty),
      ],
    );

    blocTest<BillingBloc, BillingState>(
      'removing a product drops only that product',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ScanBarcodeEvent('1111'))
        ..add(const ScanBarcodeEvent('2222'))
        ..add(const RemoveProductFromCartEvent('1')),
      skip: 2,
      expect: () => [
        isA<BillingState>()
            .having((s) => s.cartItems.length, 'len', 1)
            .having((s) => s.cartItems.first.product, 'product', chips),
      ],
    );

    blocTest<BillingBloc, BillingState>(
      'clearing the cart resets to the initial state',
      build: buildBloc,
      act: (bloc) => bloc
        ..add(const ScanBarcodeEvent('1111'))
        ..add(ClearCartEvent()),
      skip: 1,
      expect: () => [const BillingState()],
    );

    test('totalAmount sums price * quantity across items', () {
      const state = BillingState(cartItems: [
        CartItem(product: cola, quantity: 3), // 240
        CartItem(product: chips, quantity: 2), // 300
      ]);
      expect(state.totalAmount, 540);
    });
  });
}
