import 'dart:convert';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../../core/data/hive_database.dart';
import '../../product/data/models/product_model.dart';
import '../../product/domain/entities/product.dart';
import '../../billing/domain/entities/cart_item.dart';

class DataTransferService {
  static Future<int> importProductsFromExcel() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    if (result == null || result.files.single.bytes == null) return 0;
    return importProductsFromBytes(result.files.single.bytes!);
  }

  static Future<int> importProductsFromBytes(List<int> bytes) async {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw Exception('Aucune feuille Excel trouvée.');
    final sheet = workbook.tables.values.first;
    if (sheet.rows.isEmpty) throw Exception('Le fichier Excel est vide.');
    final headers = sheet.rows.first.map((c) => _value(c?.value).trim().toLowerCase()).toList();
    int find(List<String> names) => headers.indexWhere((h) => names.any((n) => h == n || h.contains(n)));
    final nameCol = find(['désignation', 'designation', 'nom', 'produit', 'name']);
    final barcodeCol = find(['code-barres', 'code barre', 'barcode', 'ean', 'code']);
    final priceCol = find(['prix', 'price', 'tarif']);
    final stockCol = find(['stock', 'quantité', 'quantite', 'quantity']);
    if (nameCol < 0 || barcodeCol < 0) throw Exception('Colonnes obligatoires introuvables : Désignation/Nom et Code-barres.');

    int imported = 0;
    for (final row in sheet.rows.skip(1)) {
      if (row.isEmpty) continue;
      String cell(int index) => index >= 0 && index < row.length ? _value(row[index]?.value).trim() : '';
      final name = cell(nameCol);
      final barcode = cell(barcodeCol);
      if (name.isEmpty || barcode.isEmpty) continue;
      final price = double.tryParse(cell(priceCol).replaceAll(',', '.')) ?? 0;
      final stock = int.tryParse(cell(stockCol)) ?? 0;
      final product = Product(id: const Uuid().v4(), name: name, barcode: barcode, price: price, stock: stock);
      await HiveDatabase.productBox.put(product.id, ProductModel.fromEntity(product));
      imported++;
    }
    return imported;
  }

  static Future<int> importProductsFromGoogleSheets(String link) async {
    final uri = _googleCsvUri(link);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Impossible de lire Google Sheets. Vérifiez que la feuille est accessible en lecture.');
    final rows = _parseCsv(response.body);
    if (rows.isEmpty) throw Exception('La feuille Google Sheets est vide.');
    final headers = rows.first.map((e) => e.trim().toLowerCase()).toList();
    int find(List<String> names) => headers.indexWhere((h) => names.any((n) => h == n || h.contains(n)));
    final nameCol = find(['désignation', 'designation', 'nom', 'produit', 'name']);
    final barcodeCol = find(['code-barres', 'code barre', 'barcode', 'ean', 'code']);
    final priceCol = find(['prix', 'price', 'tarif']);
    final stockCol = find(['stock', 'quantité', 'quantite', 'quantity']);
    if (nameCol < 0 || barcodeCol < 0) throw Exception('Colonnes obligatoires introuvables dans Google Sheets.');
    int imported = 0;
    for (final row in rows.skip(1)) {
      String cell(int index) => index >= 0 && index < row.length ? row[index].trim() : '';
      final name = cell(nameCol), barcode = cell(barcodeCol);
      if (name.isEmpty || barcode.isEmpty) continue;
      final product = Product(id: const Uuid().v4(), name: name, barcode: barcode, price: double.tryParse(cell(priceCol).replaceAll(',', '.')) ?? 0, stock: int.tryParse(cell(stockCol)) ?? 0);
      await HiveDatabase.productBox.put(product.id, ProductModel.fromEntity(product));
      imported++;
    }
    return imported;
  }

  static Future<void> exportSaleToExcel({required List<CartItem> items, required double total}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Ventes'];
    final rows = [
      ['Produit', 'Code-barres', 'Quantité', 'Prix unitaire (DA)', 'Total (DA)'],
      ...items.map((i) => [i.product.name, i.product.barcode, i.quantity, i.product.price, i.total]),
      ['TOTAL', '', '', '', total],
    ];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(rows[r][c].toString());
      }
    }
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Impossible de générer le fichier Excel.');
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Enregistrer la facture', fileName: 'facture_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx'], bytes: bytes);
    if (path == null) return;
  }

  static Future<void> exportSaleToGoogleSheets({required List<CartItem> items, required double total, required String endpoint}) async {
    final url = endpoint.trim();
    if (url.isEmpty) throw Exception('Configurez d’abord l’URL Google Apps Script dans les paramètres.');
    final payload = {'date': DateTime.now().toIso8601String(), 'currency': 'DZD', 'total': total, 'items': items.map((i) => {'produit': i.product.name, 'codeBarres': i.product.barcode, 'quantite': i.quantity, 'prixUnitaire': i.product.price, 'total': i.total}).toList()};
    final response = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload)).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Échec de l’export Google Sheets (${response.statusCode}).');
  }

  static Uri _googleCsvUri(String link) {
    final uri = Uri.parse(link.trim());
    final match = RegExp(r'/spreadsheets/d/([^/]+)').firstMatch(uri.path);
    if (match == null) throw Exception('Lien Google Sheets invalide.');
    final gid = uri.queryParameters['gid'];
    final params = {'tqx': 'out:csv', if (gid != null) 'gid': gid};
    return Uri.parse('https://docs.google.com/spreadsheets/d/${match.group(1)}/gviz/tq').replace(queryParameters: params);
  }

  static String _value(CellValue? value) => switch (value) { null => '', TextCellValue v => v.value, IntCellValue v => v.value.toString(), DoubleCellValue v => v.value.toString(), BoolCellValue v => v.value.toString(), DateCellValue v => v.toString(), DateTimeCellValue v => v.toString(), TimeCellValue v => v.toString(), FormulaCellValue v => v.formula };

  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[]; final row = <String>[]; final cell = StringBuffer(); bool quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') { if (quoted && i + 1 < text.length && text[i + 1] == '"') { cell.write('"'); i++; } else { quoted = !quoted; } }
      else if (ch == ',' && !quoted) { row.add(cell.toString()); cell.clear(); }
      else if ((ch == '\n' || ch == '\r') && !quoted) { if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++; row.add(cell.toString()); cell.clear(); rows.add(List<String>.from(row)); row.clear(); }
      else { cell.write(ch); }
    }
    if (cell.isNotEmpty || row.isNotEmpty) { row.add(cell.toString()); rows.add(row); }
    return rows;
  }
}
