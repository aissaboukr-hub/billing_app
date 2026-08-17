import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../domain/entities/cart_item.dart';
import '../../../../core/utils/app_formatters.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../product/domain/entities/product.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // Scanner configuré pour les codes-barres 1D courants et les QR codes.
  // La détection normale avec un petit délai est plus réactive que noDuplicates
  // sur les petits codes imprimés sur des objets courbés.
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 120,
    cameraResolution: const Size(1920, 1080),
    useNewCameraSelector: true,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf,
      BarcodeFormat.qrCode,
    ],
    returnImage: false,
  );

  bool _isCameraOn = true;
  bool _isFlashOn = false;
  bool _searchMode = false;
  bool _cameraStarting = false;
  final TextEditingController _searchController = TextEditingController();

  // Cooldown mapping to prevent rapid firing of the same barcode.
  final Map<String, DateTime> _lastScanTimes = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScanner();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nous gérons explicitement le cycle de vie pour éviter les caméras
    // bloquées après navigation ou retour depuis l'arrière-plan.
    if (state == AppLifecycleState.resumed) {
      if (_isCameraOn && !_searchMode && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 300), _startScanner);
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopScanner();
    }
  }

  Future<void> _startScanner() async {
    if (!mounted || !_isCameraOn || _searchMode || _cameraStarting) return;
    _cameraStarting = true;
    try {
      await _scannerController.start();
    } catch (_) {
      // Une transition de route ou une permission caméra peut interrompre start().
    } finally {
      _cameraStarting = false;
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _scannerController.stop();
    } catch (_) {
      // stop() est volontairement idempotent côté application.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.stop();
    _scannerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_isCameraOn || _searchMode || _cameraStarting) return;

    // Si plusieurs codes sont présents dans l'image, privilégier celui qui
    // occupe la plus grande surface : c'est généralement le code présenté
    // dans le cadre et non un code voisin sur l'emballage.
    Barcode? bestBarcode;
    double bestArea = 0;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      final size = barcode.size;
      final area = size.width * size.height;
      if (bestBarcode == null || area > bestArea) {
        bestBarcode = barcode;
        bestArea = area;
      }
    }

    final rawValue = bestBarcode?.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final now = DateTime.now();
    final lastScan = _lastScanTimes[rawValue];
    if (lastScan != null && now.difference(lastScan).inSeconds < 2) return;
    _lastScanTimes[rawValue] = now;

    await _scannerController.stop();
    if (mounted) {
      context.read<BillingBloc>().add(ScanBarcodeEvent(rawValue));
    }
  }

  Future<void> _restartScanner() async {
    if (!mounted || !_isCameraOn || _searchMode) return;
    await _stopScanner();
    // Laisser CameraX/AVFoundation libérer complètement la session avant
    // de la recréer. Cela évite les écrans noirs et les scanners figés.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted && _isCameraOn && !_searchMode) {
      await _startScanner();
    }
  }

  void _showTopBanner(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(message),
        leading: Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            color: error ? Colors.red : Colors.green),
        backgroundColor: error ? Colors.red.shade50 : Colors.green.shade50,
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) messenger.hideCurrentMaterialBanner();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<BillingBloc, BillingState>(
        listenWhen: (previous, current) {
          final cartChanged = previous.cartItems != current.cartItems;
          final errorChanged = previous.error != current.error;
          return cartChanged || (errorChanged && current.error != null);
        },
        listener: (context, state) async {
          if (state.error != null) {
            await SystemSound.play(SystemSoundType.alert);
            _showTopBanner(state.error!, error: true);
            await _restartScanner();
            return;
          }
          await SystemSound.play(SystemSoundType.click);
          final last = state.cartItems.isEmpty ? null : state.cartItems.last.product.name;
          _showTopBanner(last == null ? 'Article ajouté au panier' : '$last ajouté au panier');
          await _restartScanner();
        },
        child: Stack(
          children: [
            // SCANNER VIEW (TOP 50%)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.4,
              child: _buildScannerSection(),
            ),

            // BOTTOM PANEL (BOTTOM 50% + OVERLAP)
            Positioned(
              top: (MediaQuery.of(context).size.height * 0.4) - 24, // overlap
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomPanel(),
            ),
          ],
        ),
      ),
      bottomSheet:
          BlocBuilder<BillingBloc, BillingState>(builder: (context, state) {
        return PrimaryButton(
          onPressed: state.cartItems.isEmpty
              ? null
              : () async {
                  await _stopScanner();
                  await context.push('/checkout');
                  await _restartScanner();
                },
          icon: Icons.payment,
          label: 'Vérifier la vente',
        );
      }),
    );
  }

  Widget _buildScannerSection() {
    if (_searchMode) return _buildSearchSection();
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Cadre horizontal large pour les codes 1D, notamment sur les
              // stylos et emballages cylindriques. Pas de zoom numérique.
              final scanWindow = Rect.fromLTWH(
                constraints.maxWidth * 0.02,
                constraints.maxHeight * 0.30,
                constraints.maxWidth * 0.96,
                constraints.maxHeight * 0.40,
              );
              return MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
                fit: BoxFit.cover,
                scanWindow: scanWindow,
              );
            },
          ),
          if (!_isCameraOn) _buildCameraOffState(),

          // Overlay Actions (Top Right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Column(
              children: [
                _buildOverlayButton(
                  icon: Icons.manage_search,
                  onPressed: () {
                    setState(() => _searchMode = true);
                    _stopScanner();
                  },
                ),
                const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: Icons.assignment_return,
                  onPressed: () async {
                    await _stopScanner();
                    await context.push('/returns');
                    await _restartScanner();
                  },
                ),
                const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: Icons.history,
                  onPressed: () async {
                    await _stopScanner();
                    await context.push('/history');
                    await _restartScanner();
                  },
                ),
                const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: Icons.settings,
                  onPressed: () async {
                    await _stopScanner();
                    await context.push('/settings');
                    await _restartScanner();
                  },
                ),
                const SizedBox(height: 16),
                if (_isCameraOn)
                  _buildOverlayButton(
                    icon:
                        _isFlashOn ? Icons.flashlight_off : Icons.flashlight_on,
                    onPressed: () {
                      setState(() => _isFlashOn = !_isFlashOn);
                      _scannerController.toggleTorch();
                    },
                  ),
                _buildOverlayButton(
                  icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  // color:  Colors.white24 ,
                  onPressed: () {
                    setState(() {
                      _isCameraOn = !_isCameraOn;
                    });
                    if (_isCameraOn) {
                      _startScanner();
                    } else {
                      _stopScanner();
                    }
                  },
                ),
              ],
            ),
          ),

          // Central Overlay Bounding Box
          if (_isCameraOn)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    // Corners
                    _buildCorner(Alignment.topLeft),
                    _buildCorner(Alignment.topRight),
                    _buildCorner(Alignment.bottomLeft),
                    _buildCorner(Alignment.bottomRight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Rechercher un produit', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(onPressed: () { setState(() => _searchMode = false); _restartScanner(); }, icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scanner'),
          IconButton(onPressed: () { setState(() => _searchMode = false); _restartScanner(); }, icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Nom ou désignation du produit', suffixIcon: IconButton(onPressed: _searchController.clear, icon: const Icon(Icons.clear))),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Expanded(child: BlocBuilder<ProductBloc, ProductState>(builder: (context, state) {
          final query = _searchController.text.trim().toLowerCase();
          final products = query.isEmpty
              ? state.products.take(20).toList()
              : state.products.where((p) => _matchesWildcardSearch(p, query)).take(30).toList();
          if (products.isEmpty) return const Center(child: Text('Aucun produit trouvé.'));
          return ListView.separated(
            itemCount: products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final product = products[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.inventory_2)),
                title: Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(product.barcode),
                trailing: Text(AppFormatters.price(product.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  context.read<BillingBloc>().add(AddProductToCartEvent(product));
                  SystemSound.play(SystemSoundType.click);
                  _showTopBanner('${product.name} ajouté au panier');
                },
              );
            },
          );
        })),
      ]),
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

  Widget _buildCameraOffState() {
    return Container(
      color: const Color(0xFF1E293B), // slate-800
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFF334155), // slate-700
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                const Icon(Icons.videocam_off, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'La caméra est désactivée',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Activez la caméra pour scanner automatiquement les codes-barres et les articles.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.videocam),
            label: const Text('Activer la caméra',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() => _isCameraOn = true);
              _startScanner();
            },
          )
        ],
      ),
    );
  }

  Widget _buildOverlayButton(
      {required IconData icon, required VoidCallback onPressed, Color? color}) {
    return Container(
      width: 44,
      height: 44,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color ?? Colors.black45,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: (alignment == Alignment.topLeft ||
                    alignment == Alignment.topRight)
                ? const BorderSide(color: Colors.greenAccent, width: 4)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.greenAccent, width: 4)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft ||
                    alignment == Alignment.bottomLeft)
                ? const BorderSide(color: Colors.greenAccent, width: 4)
                : BorderSide.none,
            right: (alignment == Alignment.topRight ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: Colors.greenAccent, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 15, offset: Offset(0, -5))
        ],
      ),
      child: Column(
        children: [
          // Drag handle indicator
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          BlocBuilder<BillingBloc, BillingState>(
            builder: (context, state) {
              final totalItems =
                  state.cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Articles scannés',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        Text('$totalItems article(s) au total',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('TOTAL',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 1.2)),
                        Text(
                          AppFormatters.price(state.totalAmount),
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).primaryColor),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1),

          // List View
          Expanded(
            child: Stack(children: [
              BlocBuilder<BillingBloc, BillingState>(
                builder: (context, state) {
                  if (state.cartItems.isEmpty) {
                    return _buildEmptyCart();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(
                        left: 15, right: 15, top: 16, bottom: 100),
                    itemCount: state.cartItems.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = state.cartItems[index];
                      return _buildCartItemCard(context, item);
                    },
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                Icon(Icons.shopping_basket, size: 40, color: Colors.grey[300]),
          ),
          const SizedBox(height: 16),
          const Text('La liste est vide',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Les articles scannés apparaîtront ici au fur et à mesure.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
    BuildContext context,
    CartItem item,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: 1,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  AppFormatters.price(item.product.price),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _circularIconButton(
                    icon: Icons.remove,
                    onPressed: () {
                      if (item.quantity > 1) {
                        context.read<BillingBloc>().add(UpdateQuantityEvent(
                            item.product.id, item.quantity - 1));
                      } else {
                        context
                            .read<BillingBloc>()
                            .add(RemoveProductFromCartEvent(item.product.id));
                      }
                    }),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _circularIconButton(
                    icon: Icons.add,
                    onPressed: () {
                      context.read<BillingBloc>().add(UpdateQuantityEvent(
                          item.product.id, item.quantity + 1));
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circularIconButton(
      {required IconData icon, required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: 20, color: Colors.grey[600]),
      ),
    );
  }

  // A floating Details/Checkout Button at the very bottom
  // Added a Stack wrapper below to overlay this button
}
