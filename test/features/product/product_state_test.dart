import 'package:billing_app/features/product/presentation/bloc/product_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductState.copyWith', () {
    test('keeps the previous message when no new one is provided', () {
      const state = ProductState(message: 'Produit ajouté avec succès');
      final next = state.copyWith(status: ProductStatus.loading);

      expect(next.message, 'Produit ajouté avec succès');
    });

    test('overwrites the message when a new one is provided', () {
      const state = ProductState(message: 'ancien message');
      final next = state.copyWith(message: 'nouveau message');

      expect(next.message, 'nouveau message');
    });

    test('clears the message when clearMessage is true', () {
      const state = ProductState(message: 'à effacer');
      final next = state.copyWith(
        status: ProductStatus.loading,
        clearMessage: true,
      );

      expect(next.message, isNull);
    });

    test('clearMessage takes precedence even if message is also passed', () {
      const state = ProductState(message: 'à effacer');
      final next = state.copyWith(
        message: 'ignoré',
        clearMessage: true,
      );

      expect(next.message, isNull);
    });
  });
}
