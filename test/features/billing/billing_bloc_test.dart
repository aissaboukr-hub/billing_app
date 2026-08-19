import 'dart:async';

import 'package:billing_app/core/error/failure.dart';
import 'package:billing_app/features/billing/domain/entities/cart_item.dart';
import 'package:billing_app/features/billing/presentation/bloc/billing_bloc.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/repositories/product_repository.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
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

/// Adds [events] to [bloc] one after another, waits until exactly
/// [expectedEmissions] states have been emitted (accounting for events that
/// internally dispatch further events, e.g. UpdateQuantityEvent(qty: 0)
/// dispatching a RemoveProductFromCartEvent), and returns every emitted
/// state in order. Avoids adding a bloc_test dependency, which conflicts
/// with hive_generator's analyzer constraint in this project.
Future<List<BillingState>> runBloc(
  BillingBloc bloc,
  List<BillingEvent> events, {
  required int expectedEmissions,
}) async {
  final states = <BillingState>[];
  final completer = Completer<void>();
  final sub = bloc.stream.listen((state) {
    states.add(state);
    if (states.length >= expectedEmissions && !completer.isCompleted) {
      completer.complete();
    }
  });

  for (final event in events) {
    bloc.add(event);
  }

  await completer.future.timeout(const Duration(seconds: 2));
  await sub.cancel();
  return states;
}

void main() {
  const cola = Product(id: '1', name: 'Cola 33cl', barcode: '1111', price: 80);
  const chips = Product(id: '2', name: 'Chips', barcode: '2222', price: 150);

  BillingBloc buildBloc() => BillingBloc(
        getProductByBarcodeUseCase:
            GetProductByBarcodeUseCase(FakeProductRepository([cola, chips])),
      );

  group('BillingBloc', () {
    test('scanning a known barcode adds it to the cart', () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [const ScanBarcodeEvent('1111')],
        expectedEmissions: 1,
      );

      expect(states.last.cartItems.length, 1);
      expect(states.last.cartItems.first.product, cola);
      expect(states.last.cartItems.first.quantity, 1);
      await bloc.close();
    });

    test(
        'scanning the same barcode twice increments quantity instead of duplicating',
        () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [const ScanBarcodeEvent('1111'), const ScanBarcodeEvent('1111')],
        expectedEmissions: 2,
      );

      expect(states.last.cartItems.length, 1);
      expect(states.last.cartItems.first.quantity, 2);
      await bloc.close();
    });

    test(
        'scanning an unknown barcode sets an error and does not touch the cart',
        () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [const ScanBarcodeEvent('9999')],
        expectedEmissions: 1,
      );

      expect(states.last.cartItems, isEmpty);
      expect(states.last.error, contains('9999'));
      await bloc.close();
    });

    test('updating quantity to zero removes the item', () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [
          const ScanBarcodeEvent('1111'),
          const UpdateQuantityEvent('1', 0),
        ],
        // 1 emission for the scan + 1 for the cascading RemoveProductFromCartEvent.
        expectedEmissions: 2,
      );

      expect(states.last.cartItems, isEmpty);
      await bloc.close();
    });

    test('removing a product drops only that product', () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [
          const ScanBarcodeEvent('1111'),
          const ScanBarcodeEvent('2222'),
          const RemoveProductFromCartEvent('1'),
        ],
        expectedEmissions: 3,
      );

      expect(states.last.cartItems.length, 1);
      expect(states.last.cartItems.first.product, chips);
      await bloc.close();
    });

    test('clearing the cart resets to the initial state', () async {
      final bloc = buildBloc();
      final states = await runBloc(
        bloc,
        [const ScanBarcodeEvent('1111'), ClearCartEvent()],
        expectedEmissions: 2,
      );

      expect(states.last, const BillingState());
      await bloc.close();
    });

    test('totalAmount sums price * quantity across items', () {
      const state = BillingState(cartItems: [
        CartItem(product: cola, quantity: 3), // 240
        CartItem(product: chips, quantity: 2), // 300
      ]);
      expect(state.totalAmount, 540);
    });
  });
}
