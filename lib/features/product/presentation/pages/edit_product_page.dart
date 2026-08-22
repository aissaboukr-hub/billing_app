import 'package:billing_app/core/widgets/input_label.dart';
import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/product_bloc.dart';
import '../../domain/entities/product.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_validators.dart';

class EditProductPage extends StatefulWidget {
  final Product product;
  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _barcode;
  late String _barcode2;
  late double _price;

  @override
  void initState() {
    super.initState();
    _name = widget.product.name;
    _barcode = widget.product.barcode;
    _barcode2 = widget.product.barcode2;
    _price = widget.product.price;
  }

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

    final normalized = {
      barcode1.toUpperCase(),
      if (barcode2.isNotEmpty) barcode2.toUpperCase(),
    };

    final otherProduct = context.read<ProductBloc>().state.products
        .where((p) => p.id != widget.product.id)
        .where((p) => p.barcodes.any(
              (code) => normalized.contains(code.toUpperCase()),
            ))
        .firstOrNull;

    if (otherProduct != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Un autre produit utilise déjà le code-barres "${otherProduct.barcodeDisplay}".',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final updatedProduct = Product(
      id: widget.product.id,
      name: _name,
      barcode: barcode1,
      barcode2: barcode2,
      price: _price,
      stock: widget.product.stock,
    );

    context.read<ProductBloc>().add(UpdateProduct(updatedProduct));
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
                  hintText: second ? 'Optionnel' : 'Code-barres principal',
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
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            size: 32,
            color: Theme.of(context).primaryColor,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Modifier le produit',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                const SizedBox(height: 12),
                _barcodeField(
                  label: 'Code-barres 2 (optionnel)',
                  value: _barcode2,
                  second: true,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Scanner l’un ou l’autre code retrouvera ce même produit.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4C669A)),
                ),
                const SizedBox(height: 24),
                const InputLabel(text: 'Nom du produit'),
                TextFormField(
                  initialValue: _name,
                  textCapitalization: TextCapitalization.words,
                  validator: AppValidators.required('Veuillez saisir un nom'),
                  onSaved: (value) => _name = value!,
                ),
                const SizedBox(height: 24),
                const InputLabel(text: 'Prix (DA)'),
                TextFormField(
                  initialValue: _price.toStringAsFixed(2),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
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
        icon: Icons.save,
        label: 'Enregistrer les modifications',
      ),
    );
  }
}
