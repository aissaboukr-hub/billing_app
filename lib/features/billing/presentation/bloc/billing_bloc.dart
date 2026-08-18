import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/cart_item.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/domain/repositories/product_repository.dart';
import 'billing_event.dart';
import 'billing_state.dart';

class BillingBloc extends Bloc<BillingEvent, BillingState> {
  final ProductRepository productRepository;

  BillingBloc({required this.productRepository}) : super(const BillingState()) {
    on<ScanBarcodeEvent>(_onScanBarcode);
    on<AddToCartEvent>(_onAddToCart);
    on<RemoveFromCartEvent>(_onRemoveFromCart);
    on<UpdateQuantityEvent>(_onUpdateQuantity);
    on<ClearCartEvent>(_onClearCart);
  }

  Future<void> _onScanBarcode(
    ScanBarcodeEvent event,
    Emitter<BillingState> emit,
  ) async {
    final result = await productRepository.getProductByBarcode(event.barcode);
    result.fold(
      (failure) => emit(state.copyWith(errorMessage: 'Produit non trouvé')),
      (product) {
        if (product != null) {
          add(AddToCartEvent(product));
        } else {
          emit(state.copyWith(errorMessage: 'Aucun produit associé à ce code-barres'));
        }
      },
    );
  }

  void _onAddToCart(AddToCartEvent event, Emitter<BillingState> emit) {
    final updatedCart = List<CartItem>.from(state.cartItems);
    final index = updatedCart.indexWhere((item) => item.product.id == event.product.id);

    if (index >= 0) {
      final existingItem = updatedCart[index];
      updatedCart[index] = existingItem.copyWith(quantity: existingItem.quantity + 1);
    } else {
      updatedCart.add(CartItem(product: event.product, quantity: 1));
    }

    emit(state.copyWith(cartItems: updatedCart, errorMessage: null));
  }

  void _onRemoveFromCart(RemoveFromCartEvent event, Emitter<BillingState> emit) {
    final updatedCart = state.cartItems.where((item) => item.product.id != event.productId).toList();
    emit(state.copyWith(cartItems: updatedCart));
  }

  void _onUpdateQuantity(UpdateQuantityEvent event, Emitter<BillingState> emit) {
    if (event.quantity <= 0) {
      add(RemoveFromCartEvent(event.productId));
      return;
    }

    final updatedCart = state.cartItems.map((item) {
      if (item.product.id == event.productId) {
        return item.copyWith(quantity: event.quantity);
      }
      return item;
    }).toList();

    emit(state.copyWith(cartItems: updatedCart));
  }

  void _onClearCart(ClearCartEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(cartItems: []));
  }
}
