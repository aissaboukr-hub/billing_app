import 'dart:convert';
import 'dart:typed_data';
import 'package:excel_community/excel_community.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/hive_database.dart';
import '../../product/data/models/product_model.dart';
import '../../product/domain/entities/product.dart';
import '../../billing/domain/entities/cart_item.dart';

class DataTransferService {
  static const defaultGoogleSheetsImportUrl =
      'https://docs.google.com/spreadsheets/d/1oa5IjH5EAinCsKtLmOx1VQ8wZd717Ll6/edit?usp=sharing&ouid=116963748618844977648&rtpof=true&sd=true';

  static const List<String> _productImportHeaders = [
    'Code-barres 1',
    'Code-barres 2',
    'Nom',
    'Prix',
  ];

  static void _validateProductHeaders(List<String> headers, {required String source}) {
    final actual = headers.map((h) => h.trim()).toList();
    final valid = actual.length == _productImportHeaders.length &&
        List.generate(_productImportHeaders.length, (i) => actual[i] == _productImportHeaders[i]).every((v) => v);
    if (!valid) {
      throw Exception(
        "Format $source invalide. Le fichier doit contenir exactement ces 4 colonnes, dans cet ordre : Code-barres 1, Code-barres 2, Nom, Prix. Aucune autre colonne n'est autorisée.",
      );
    }
  }

  static String _value(CellValue? value) => switch (value) {
    null => '',
    TextCellValue v => v.value.toString(),
    IntCellValue v => v.value.toString(),
    DoubleCellValue v => v.value.toString(),
    BoolCellValue v => v.value.toString(),
    DateCellValue v => v.toString(),
    DateTimeCellValue v => v.toString(),
    TimeCellValue v => v.toString(),
    FormulaCellValue v => v.formula.toString(),
  };

  static void _validateRowWidth(List<dynamic> row, int rowNumber, String source) {
    if (row.length <= 4) return;
    final hasExtraData = row.skip(4).any((cell) => _value(cell?.value).trim().isNotEmpty);
    if (hasExtraData) {
      throw Exception("Ligne $rowNumber invalide dans $source : aucune colonne supplémentaire n'est autorisée.");
    }
  }

  static Future<List<List<String>>> _readExcelRows(List<int> bytes) async {
    final workbook = Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw Exception('Aucune feuille Excel trouvée.');
    final sheet = workbook.tables.values.first;
    if (sheet.rows.isEmpty) throw Exception('Le fichier Excel est vide.');
    final headers = sheet.rows.first.map((c) => _value(c?.value).trim()).toList();
    _validateProductHeaders(headers, source: 'Excel');
    return sheet.rows.skip(1).map((row) {
      _validateRowWidth(row, sheet.rows.indexOf(row) + 1, 'Excel');
      return List.generate(4, (i) => i < row.length ? _value(row[i]?.value).trim() : '');
    }).toList();
  }

  static Future<int> importProductsFromExcel() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    if (result == null || result.files.single.bytes == null) return 0;
    return _insertProducts(await _readExcelRows(result.files.single.bytes!));
  }

  static Future<int> updateProductsFromExcel() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
    if (result == null || result.files.single.bytes == null) return 0;
    return _upsertProducts(await _readExcelRows(result.files.single.bytes!));
  }

  static Future<List<List<String>>> _readGoogleRows(String link) async {
    final uri = _googleCsvUri(link);
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Impossible de lire Google Sheets. Vérifiez que la feuille est accessible en lecture.');
    }
    final rows = _parseCsv(response.body);
    if (rows.isEmpty) throw Exception('La feuille Google Sheets est vide.');
    _validateProductHeaders(rows.first, source: 'Google Sheets');
    return rows.skip(1).map((row) {
      if (row.length > 4 && row.skip(4).any((cell) => cell.trim().isNotEmpty)) {
        throw Exception("Ligne ${rows.indexOf(row) + 1} invalide dans Google Sheets : aucune colonne supplémentaire n'est autorisée.");
      }
      return List.generate(4, (i) => i < row.length ? row[i].trim() : '');
    }).toList();
  }

  static Future<int> importProductsFromGoogleSheets(String link) async =>
      _insertProducts(await _readGoogleRows(link));

  static Future<int> updateProductsFromGoogleSheets(String link) async =>
      _upsertProducts(await _readGoogleRows(link));

  static Product _productFromRow(List<String> row, {String? id, int stock = 0}) {
    final barcode1 = row[0].trim();
    final barcode2 = row[1].trim();
    final name = row[2].trim();
    final priceText = row[3].trim().replaceAll(',', '.');
    if (barcode1.isEmpty) throw Exception('Code-barres 1 est obligatoire.');
    if (name.isEmpty) throw Exception('Nom est obligatoire.');
    final price = double.tryParse(priceText);
    if (price == null) throw Exception('Prix doit être un nombre.');
    return Product(id: id ?? const Uuid().v4(), name: name, barcode: barcode1, barcode2: barcode2, price: price, stock: stock);
  }

  static Future<int> _insertProducts(List<List<String>> rows) async {
    int count = 0;
    int rowNumber = 2;
    final box = HiveDatabase.productBox;
    for (final row in rows) {
      if (row.every((v) => v.isEmpty)) { rowNumber++; continue; }
      try {
        final product = _productFromRow(row);
        final incomingCodes = product.barcodes
            .map((v) => v.trim().toUpperCase())
            .where((v) => v.isNotEmpty)
            .toSet();
        Product? existing;
        for (final current in box.values) {
          final currentCodes = current.barcodes
              .map((v) => v.trim().toUpperCase())
              .where((v) => v.isNotEmpty)
              .toSet();
          if (currentCodes.intersection(incomingCodes).isNotEmpty) {
            existing = current;
            break;
          }
        }
        if (existing != null) {
          throw Exception(
            'Le produit existe déjà (code-barres correspondant : ${incomingCodes.intersection(existing.barcodes.map((v) => v.trim().toUpperCase()).toSet()).first}). Utilisez « Mise à jour » pour modifier ce produit.',
          );
        }
        await box.put(product.id, ProductModel.fromEntity(product));
        count++;
      } catch (e) {
        throw Exception('Ligne $rowNumber invalide : ${e.toString().replaceFirst('Exception: ', '')}');
      }
      rowNumber++;
    }
    return count;
  }

  static Future<int> _upsertProducts(List<List<String>> rows) async {
    int count = 0;
    int rowNumber = 2;
    final box = HiveDatabase.productBox;
    for (final row in rows) {
      if (row.every((v) => v.isEmpty)) { rowNumber++; continue; }
      try {
        final incoming = _productFromRow(row);
        final incomingCodes = incoming.barcodes.map((v) => v.toUpperCase()).toSet();
        Product? existing;
        for (final product in box.values) {
          if (product.barcodes.map((v) => v.toUpperCase()).any(incomingCodes.contains)) {
            existing = product;
            break;
          }
        }
        final product = existing == null
            ? incoming
            : Product(id: existing.id, name: incoming.name, barcode: incoming.barcode, barcode2: incoming.barcode2, price: incoming.price, stock: existing.stock);
        await box.put(product.id, ProductModel.fromEntity(product));
        count++;
      } catch (e) {
        throw Exception('Ligne $rowNumber invalide : ${e.toString().replaceFirst('Exception: ', '')}');
      }
      rowNumber++;
    }
    return count;
  }

  static List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    bool quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') { cell.write('"'); i++; }
        else { quoted = !quoted; }
      } else if (ch == ',' && !quoted) {
        row.add(cell.toString()); cell.clear();
      } else if ((ch == '\n' || ch == '\r') && !quoted) {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString()); cell.clear();
        if (row.any((v) => v.isNotEmpty)) rows.add(List<String>.from(row));
        row.clear();
      } else { cell.write(ch); }
    }
    if (cell.isNotEmpty || row.isNotEmpty) { row.add(cell.toString()); rows.add(List<String>.from(row)); }
    return rows;
  }

  static Uri _googleCsvUri(String link) {
    final uri = Uri.parse(link.trim());
    final match = RegExp(r'/spreadsheets/d/([^/]+)').firstMatch(uri.path);
    if (match == null) throw Exception('Lien Google Sheets invalide.');
    final gid = uri.queryParameters['gid'];
    return Uri.parse('https://docs.google.com/spreadsheets/d/${match.group(1)}/gviz/tq').replace(queryParameters: {'tqx': 'out:csv', if (gid != null) 'gid': gid});
  }

  static Uint8List _historyExcelBytes({required List<Map<String, dynamic>> history}) {
    if (history.isEmpty) throw Exception('Aucune opération à exporter.');
    final excel = Excel.createExcel();
    final sheet = excel['Historique'];
    final rows = <List<String>>[
      ['ID', 'Date', 'Type', 'Produit', 'Code-barres', 'Quantité', 'Prix unitaire (DA)', 'Total ligne (DA)', 'Total opération (DA)', 'Devise', 'Erreur'],
    ];
    for (final operation in history) {
      final items = (operation['items'] as List?) ?? const [];
      if (items.isEmpty) {
        rows.add(['${operation['id'] ?? ''}', '${operation['date'] ?? ''}', '${operation['type'] ?? ''}', '', '', '', '', '', '${operation['total'] ?? 0}', '${operation['currency'] ?? 'DZD'}', '${operation['error'] ?? ''}']);
      } else {
        for (final rawItem in items) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          rows.add(['${operation['id'] ?? ''}', '${operation['date'] ?? ''}', '${operation['type'] ?? ''}', '${item['produit'] ?? ''}', '${item['codeBarres'] ?? ''}', '${item['quantite'] ?? 0}', '${item['prixUnitaire'] ?? 0}', '${item['total'] ?? 0}', '${operation['total'] ?? 0}', '${operation['currency'] ?? 'DZD'}', '${operation['error'] ?? ''}']);
        }
      }
    }
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value = TextCellValue(rows[r][c]);
      }
    }
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Impossible de générer le fichier Excel.');
    return Uint8List.fromList(bytes);
  }

  static Future<void> exportHistoryToExcel({required List<Map<String, dynamic>> history}) async {
    final bytes = _historyExcelBytes(history: history);
    await FilePicker.saveFile(dialogTitle: 'Exporter l’historique', fileName: 'historique_${DateTime.now().millisecondsSinceEpoch}.xlsx', type: FileType.custom, allowedExtensions: ['xlsx'], bytes: bytes);
  }

  static Future<void> shareHistoryExcel({required List<Map<String, dynamic>> history}) async {
    final bytes = _historyExcelBytes(history: history);
    final fileName = 'historique_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await Share.shareXFiles([XFile.fromData(bytes, name: fileName, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')], subject: 'Historique des opérations', text: 'Historique des opérations');
  }

  static Future<void> exportHistoryToGoogleSheets({required List<Map<String, dynamic>> history, required String endpoint}) async {
    final url = endpoint.trim();
    if (url.isEmpty) throw Exception('Configurez d’abord l’URL Google Apps Script dans les paramètres.');
    if (history.isEmpty) throw Exception('Aucune opération à synchroniser.');
    final response = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'currency': 'DZD', 'history': history})).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Échec de la synchronisation Google Sheets (${response.statusCode}).');
  }
}
