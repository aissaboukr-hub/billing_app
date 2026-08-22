import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/data_transfer_service.dart';
import '../../../product/presentation/bloc/product_bloc.dart';

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  late final TextEditingController _url;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: DataTransferService.defaultGoogleSheetsImportUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<int> Function() action, {required String verb}) async {
    setState(() => _loading = true);
    try {
      final n = await action();
      if (mounted) {
        context.read<ProductBloc>().add(LoadProducts());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$n produit(s) $verb.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _googleLinkEmpty => _url.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importation / Mise à jour')), 
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Importer la liste', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Importer depuis Excel'),
              subtitle: const Text('Ajoute les produits du fichier à la liste existante.'),
              onTap: _loading ? null : () => _run(DataTransferService.importProductsFromExcel, verb: 'importé(s)'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Importer depuis Google Sheets'),
              subtitle: const Text('Ajoute les produits de la feuille à la liste existante.'),
              onTap: _loading || _googleLinkEmpty ? null : () => _run(() => DataTransferService.importProductsFromGoogleSheets(_url.text), verb: 'importé(s)'),
            ),
          ),
          const SizedBox(height: 28),
          const Text('Mettre à jour la liste', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Un produit est reconnu grâce à Code-barres 1 ou Code-barres 2. Son prix, son nom et ses codes sont mis à jour. Le stock actuel est conservé.'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.table_view),
              title: const Text('Mettre à jour depuis Excel'),
              subtitle: const Text('Ajoute les nouveaux produits et actualise les produits existants.'),
              onTap: _loading ? null : () => _run(DataTransferService.updateProductsFromExcel, verb: 'mis à jour'),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Mettre à jour depuis Google Sheets'),
              subtitle: const Text('Ajoute les nouveaux produits et actualise les produits existants.'),
              onTap: _loading || _googleLinkEmpty ? null : () => _run(() => DataTransferService.updateProductsFromGoogleSheets(_url.text), verb: 'mis à jour'),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Lien Google Sheets',
              hintText: 'https://docs.google.com/spreadsheets/d/...',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          const Text('Format obligatoire', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Excel et Google Sheets doivent contenir exactement 4 colonnes, dans cet ordre : Code-barres 1, Code-barres 2, Nom, Prix. Aucune autre colonne n’est autorisée. Code-barres 2 est facultatif.'),
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
