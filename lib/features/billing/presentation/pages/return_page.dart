import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';
import '../../../history/data/history_service.dart';
import '../../../../core/utils/app_formatters.dart';

class ReturnPage extends StatefulWidget {
  const ReturnPage({super.key});

  @override
  State<ReturnPage> createState() => _ReturnPageState();
}

class _ReturnPageState extends State<ReturnPage> {
  final TextEditingController _searchController = TextEditingController();
  Product? _selectedProduct;
  int _quantity = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmReturn() async {
    final product = _selectedProduct;
    if (product == null) return;
    final total = product.price * _quantity;
    await HistoryService.addReturn(product: product, quantity: _quantity, total: total);
    if (!mounted) return;
    await SystemSound.play(SystemSoundType.click);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Retour enregistré : ${product.name}')),
    );
    setState(() {
      _selectedProduct = null;
      _quantity = 1;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des retours'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: BlocBuilder<ProductBloc, ProductState>(
        builder: (context, state) {
          final query = _searchController.text.trim().toLowerCase();
          final products = query.isEmpty
              ? state.products.take(30).toList()
              : state.products.where((p) => _matchesWildcardSearch(p, query)).take(30).toList();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Rechercher l’article',
                    hintText: 'Désignation ou code-barres',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(onPressed: _searchController.clear, icon: const Icon(Icons.clear)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _selectedProduct == null
                      ? ListView.separated(
                          itemCount: products.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final product = products[index];
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.assignment_return)),
                              title: Text(product.name),
                              subtitle: Text(product.barcode),
                              trailing: Text(AppFormatters.price(product.price)),
                              onTap: () => setState(() => _selectedProduct = product),
                            );
                          },
                        )
                      : _buildReturnForm(_selectedProduct!),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _matchesWildcardSearch(Product product, String query) {
    final name = product.name.toLowerCase();
    final barcode = product.barcode.toLowerCase();
    final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
    for (final term in terms) {
      final pattern = RegExp.escape(term).replaceAll('%', '.*');
      final regex = RegExp(pattern, caseSensitive: false);
      if (!regex.hasMatch(name) && !regex.hasMatch(barcode)) return false;
    }
    return true;
  }

  Widget _buildReturnForm(Product product) {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Article à retourner', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(product.barcode),
              const SizedBox(height: 8),
              Text('Prix unitaire : ${AppFormatters.price(product.price)}'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null, icon: const Icon(Icons.remove_circle_outline), iconSize: 36),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('$_quantity', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add_circle_outline), iconSize: 36),
          ],
        ),
        const SizedBox(height: 16),
        Text('Montant du retour : ${AppFormatters.price(product.price * _quantity)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _confirmReturn, icon: const Icon(Icons.check), label: const Text('Enregistrer le retour')),
        TextButton(onPressed: () => setState(() { _selectedProduct = null; _quantity = 1; }), child: const Text('Changer d’article')),
      ],
    );
  }
}
