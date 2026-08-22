import 'package:hive/hive.dart';
import '../../domain/entities/product.dart';

part 'product_model.g.dart';

@HiveType(typeId: 0)
class ProductModel extends Product {
  @override
  @HiveField(0)
  final String id;

  @override
  @HiveField(1)
  final String name;

  @override
  @HiveField(2)
  final String barcode;

  @override
  @HiveField(3)
  final double price;

  @override
  @HiveField(4)
  final int stock;

  /// Champ Hive 5 : ajouté pour conserver le deuxième code-barres.
  /// Les anciennes données Hive n'ont pas ce champ et utilisent donc ''.
  @override
  @HiveField(5)
  final String barcode2;

  const ProductModel({
    required this.id,
    required this.name,
    required this.barcode,
    this.barcode2 = '',
    required this.price,
    required this.stock,
  }) : super(
          id: id,
          name: name,
          barcode: barcode,
          barcode2: barcode2,
          price: price,
          stock: stock,
        );

  factory ProductModel.fromEntity(Product product) {
    return ProductModel(
      id: product.id,
      name: product.name,
      barcode: product.barcode,
      barcode2: product.barcode2,
      price: product.price,
      stock: product.stock,
    );
  }

  Product toEntity() {
    return Product(
      id: id,
      name: name,
      barcode: barcode,
      barcode2: barcode2,
      price: price,
      stock: stock,
    );
  }
}
