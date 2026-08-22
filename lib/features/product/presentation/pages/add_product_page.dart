import 'package:billing_app/core/widgets/input_label.dart';
import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../bloc/product_bloc.dart';
import '../../domain/entities/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_validators.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _barcode = '';
  String _barcode2 = '';
  double _price = 0.0;

  Future<void> _scanBarcode({required bool second}) async {
    final result = await context.push<String>('/scanner');
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        if (second) {
          _barcode2 = result.trim();
        } else {
          _barcode = result.trim();
        }
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final barcode1 = _barcode.trim();
    final barcode2 = _barcode2.trim();

    if (barcode2.isNotEmpty &&
        barcode1.toUpperCase() == barcode2.toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les deux codes-barres doivent être différents.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final productState = context.read<ProductBloc>().state;
    final normalized = {barcode1.toUpperCase(), if (barcode2.isNotEmpty) barcode2.toUpperCase()};

    final existingProduct = productState.products
        .where((p) => p.barcodes.any(
              (code) => normalized.contains(code.toUpperCase()),
            ))
        .firstOrNull;

    if (existingProduct != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Un produit utilise déjà le code-barres "${existingProduct.barcodeDisplay}".',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final product = Product(
      id: const Uuid().v4(),
      name: _name,
      barcode: barcode1,
      barcode2: barcode2,
      price: _price,
    );

    context.read<ProductBloc>().add(AddProduct(product));
    context.pop();
  }

  Widget _barcodeField({
    required String label,
    required String value,
    required bool second,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputLabel(text: label),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('${second ? 'barcode2' : 'barcode1'}-$value'),
                initialValue: value,
                decoration: InputDecoration(
                  hintText: second
                      ? 'Optionnel'
                      : 'Scanner ou saisir le code-barres',
                ),
                validator: second
                    ? null
                    : AppValidators.required('Veuillez saisir un code-barres'),
                onSaved: (v) {
                  if (second) {
                    _barcode2 = v?.trim() ?? '';
                  } else {
                    _barcode = v?.trim() ?? '';
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.qr_code_scanner,
                  color: AppTheme.primaryColor,
                ),
                tooltip: 'Scanner $label',
                onPressed: () => _scanBarcode(second: second),
                padding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            size: 28,
            color: Theme.of(context).primaryColor,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Ajouter un produit',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _barcodeField(
                  label: 'Code-barres 1',
                  value: _barcode,
                  second: false,
                ),
                const SizedBox(height: 10),
                _barcodeField(
                  label: 'Code-barres 2 (optionnel)',
                  value: _barcode2,
                  second: true,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Les deux codes-barres peuvent désigner le même produit. '
                  'Un scan de l’un ou de l’autre ajoutera le produit au panier.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4C669A)),
                ),
                const SizedBox(height: 24),
                const InputLabel(text: 'Nom du produit'),
                TextFormField(
                  decoration: const InputDecoration(
                    hintText: 'Ex. Riz Basmati',
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: AppValidators.required('Veuillez saisir un nom'),
                  onSaved: (value) => _name = value!,
                ),
                const SizedBox(height: 24),
                const InputLabel(text: 'Prix (DA)'),
                TextFormField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    prefixText: 'DA ',
                    prefixStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  validator: AppValidators.price,
                  onSaved: (value) => _price = double.parse(value!),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: PrimaryButton(
        onPressed: _submit,
        icon: Icons.add_circle,
        label: 'Ajouter un produit',
      ),
    );
  }
}
