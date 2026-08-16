import 'package:uuid/uuid.dart';
import '../../../../core/data/hive_database.dart';
import '../../../billing/domain/entities/cart_item.dart';

class HistoryService {
  static const _key = 'operations_history';
  static const _uuid = Uuid();

  static List<Map<String, dynamic>> getAll() {
    final raw = HiveDatabase.settingsBox.get(_key, defaultValue: <dynamic>[]);
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Future<void> addSale({required List<CartItem> items, required double total}) async {
    final history = getAll();
    history.insert(0, {
      'id': _uuid.v4(),
      'type': 'Vente',
      'date': DateTime.now().toIso8601String(),
      'total': total,
      'currency': 'DZD',
      'items': items.map((item) => {
        'produit': item.product.name,
        'codeBarres': item.product.barcode,
        'quantite': item.quantity,
        'prixUnitaire': item.product.price,
        'total': item.total,
      }).toList(),
    });
    await HiveDatabase.settingsBox.put(_key, history);
  }

  static Future<void> clear() async => HiveDatabase.settingsBox.delete(_key);
}
