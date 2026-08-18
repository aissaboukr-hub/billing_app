import 'package:equatable/equatable.dart';
import '../../domain/entities/cart_item.dart';

class BillingState extends Equatable {
  final List<CartItem> cartItems;
  final bool isPrinting;
  final String? errorMessage;

  const BillingState({
    this.cartItems = const [],
    this.isPrinting = false,
    this.errorMessage,
  });

  double get totalAmount => cartItems.fold(0.0, (sum, item) => sum + item.total);

  BillingState copyWith({
    List<CartItem>? cartItems,
    bool? isPrinting,
    String? errorMessage,
  }) {
    return BillingState(
      cartItems: cartItems ?? this.cartItems,
      isPrinting: isPrinting ?? this.isPrinting,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [cartItems, isPrinting, errorMessage];
}