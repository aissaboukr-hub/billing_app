import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/data_transfer_service.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});
  @override State<ImportExportPage> createState() => _ImportExportPageState();
}
class _ImportExportPageState extends State<ImportExportPage> {
  final _url = TextEditingController(); bool _loading = false;
  @override void dispose() { _url.dispose(); super.dispose(); }
  Future<void> _run(Future<int> Function() action) async { setState(() => _loading = true); try { final n = await action(); if (mounted) { context.read<ProductBloc>().add(LoadProducts()); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n produit(s) importé(s).'), backgroundColor: Colors.green)); } } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red)); } finally { if (mounted) setState(() => _loading = false); } }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Importation / Exportation')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Importer les produits', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
    Card(child: ListTile(leading: const Icon(Icons.table_view), title: const Text('Importer depuis Excel'), subtitle: const Text('Excel .xlsx/.xls • exactement 4 colonnes : Code-barres 1, Code-barres 2, Nom, Prix'), onTap: _loading ? null : () => _run(DataTransferService.importProductsFromExcel))),
    const SizedBox(height: 12),
    TextField(controller: _url, decoration: const InputDecoration(labelText: 'Lien Google Sheets', hintText: 'https://docs.google.com/spreadsheets/d/...', prefixIcon: Icon(Icons.link))),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: _loading ? null : () { if (_url.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saisissez un lien Google Sheets.'))); return; } _run(() => DataTransferService.importProductsFromGoogleSheets(_url.text)); }, icon: const Icon(Icons.cloud_download), label: const Text('Importer depuis Google Sheets')),
    const SizedBox(height: 28),
    const Text('Remarque', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6),
    const Text("Pour l’import Google Sheets, la feuille doit être accessible en lecture. La feuille doit contenir exactement 4 colonnes, dans cet ordre : Code-barres 1, Code-barres 2, Nom, Prix. Aucune autre colonne n’est autorisée. Code-barres 2 est facultatif."),
  ]));
}
