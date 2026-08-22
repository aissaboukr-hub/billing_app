import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final String id;
  final String name;

  /// Premier code-barres du produit.
  final String barcode;

  /// Deuxième code-barres optionnel du même produit.
  ///
  /// Un scan de [barcode] OU [barcode2] retrouve le même produit.
  final String barcode2;

  final double price;
  final int stock;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    this.barcode2 = '',
    required this.price,
    this.stock = 0,
  });

  /// Tous les codes-barres associés à ce produit.
  List<String> get barcodes => [
        barcode.trim(),
        barcode2.trim(),
      ].where((value) => value.isNotEmpty).toList(growable: false);

  /// Utile pour les recherches texte.
  String get barcodeDisplay => barcodes.join(' / ');

  @override
  List<Object?> get props => [id, name, barcode, barcode2, price, stock];
}
