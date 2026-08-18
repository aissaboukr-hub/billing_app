import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/cart_item.dart';
import '../../../product/domain/entities/product.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../../../../core/utils/printer_helper.dart';
import 'billing_event.dart';
import 'billing_state.dart';

class BillingBloc extends Bloc<BillingEvent, BillingState> {
  final ProductRepository productRepository;
  final PrinterHelper printerHelper;

  BillingBloc({
    required this.productRepository,
    PrinterHelper? printerHelper,
  })  : printerHelper = printerHelper ?? PrinterHelper(),
        super(const BillingState()) {
    on<ScanBarcodeEvent>(_onScanBarcode);
    on<AddProductToCartEvent>(_onAddProductToCart);
    on<RemoveProductFromCartEvent>(_onRemoveProductFromCart);
    on<UpdateQuantityEvent>(_onUpdateQuantity);
    on<ClearCartEvent>(_onClearCart);
    on<PrintReceiptEvent>(_onPrintReceipt);
  }

  Future<void> _onScanBarcode(
    ScanBarcodeEvent event,
    Emitter<BillingState> emit,
  ) async {
    final result = await productRepository.getProductByBarcode(event.barcode);

    result.fold(
      (failure) => emit(
        state.copyWith(error: 'Produit non trouvé'),
      ),
      (product) => add(AddProductToCartEvent(product)),
    );
  }

  void _onAddProductToCart(
    AddProductToCartEvent event,
    Emitter<BillingState> emit,
  ) {
    final updatedCart = List<CartItem>.from(state.cartItems);
    final index = updatedCart.indexWhere(
      (item) => item.product.id == event.product.id,
    );

    if (index >= 0) {
      final existingItem = updatedCart[index];
      updatedCart[index] = existingItem.copyWith(
        quantity: existingItem.quantity + 1,
      );
    } else {
      updatedCart.add(
        CartItem(product: event.product, quantity: 1),
      );
    }

    emit(
      state.copyWith(
        cartItems: updatedCart,
        clearError: true,
      ),
    );
  }

  void _onRemoveProductFromCart(
    RemoveProductFromCartEvent event,
    Emitter<BillingState> emit,
  ) {
    final updatedCart = state.cartItems
        .where((item) => item.product.id != event.productId)
        .toList();

    emit(state.copyWith(cartItems: updatedCart));
  }

  void _onUpdateQuantity(
    UpdateQuantityEvent event,
    Emitter<BillingState> emit,
  ) {
    if (event.quantity <= 0) {
      add(RemoveProductFromCartEvent(event.productId));
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

  void _onClearCart(
    ClearCartEvent event,
    Emitter<BillingState> emit,
  ) {
    emit(state.copyWith(cartItems: []));
  }

  Future<void> _onPrintReceipt(
    PrintReceiptEvent event,
    Emitter<BillingState> emit,
  ) async {
    if (state.cartItems.isEmpty) {
      emit(state.copyWith(error: 'Le panier est vide'));
      return;
    }

    emit(state.copyWith(
      isPrinting: true,
      printSuccess: false,
      clearError: true,
    ));

    try {
      final items = state.cartItems.map((item) {
        return <String, dynamic>{
          'name': item.product.name,
          'qty': item.quantity,
          'price': item.product.price.toStringAsFixed(2),
          'total': item.total.toStringAsFixed(2),
        };
      }).toList();

      await printerHelper.printReceipt(
        shopName: event.shopName,
        address1: event.address1,
        address2: event.address2,
        phone: event.phone,
        items: items,
        total: state.totalAmount,
        footer: event.footer,
      );

      emit(state.copyWith(
        isPrinting: false,
        printSuccess: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        isPrinting: false,
        printSuccess: false,
        error: 'Erreur d’impression : $e',
      ));
    }
  }
}
