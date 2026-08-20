import 'dart:async';

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
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  bool _isCameraOn = true;
  bool _isFlashOn = false;
  bool _searchMode = false;
  bool _quickActionsExpanded = false;
  // Mode de lecture par défaut : douchette (USB/Bluetooth type clavier).
  // La caméra reste disponible via le bouton de bascule.
  bool _douchetteMode = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _douchetteFocusNode = FocusNode(debugLabel: 'douchette_barcode');
  final StringBuffer _douchetteBuffer = StringBuffer();
  Timer? _douchetteInputTimer;
  static const Duration _douchetteInputTimeout = Duration(milliseconds: 120);

  // Verrouillage anti-déclenchements répétés du scanner.
  // Même si MobileScanner envoie plusieurs captures très rapidement,
  // un seul scan est traité à la fois.
  static const Duration _scanCooldown = Duration(milliseconds: 1800);
  final Map<String, DateTime> _lastScanTimes = {};
  bool _scanLocked = false;
  Timer? _scanUnlockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_douchetteMode && !_searchMode && mounted) {
        _requestDouchetteFocus();
      } else if (_isCameraOn && !_searchMode && mounted) {
        _scannerController.start();
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _scannerController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _scanUnlockTimer?.cancel();
    _douchetteInputTimer?.cancel();
    _douchetteFocusNode.dispose();
    _scannerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _requestDouchetteFocus() {
    if (!mounted || !_douchetteMode || _searchMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _douchetteMode && !_searchMode) {
        _douchetteFocusNode.requestFocus();
      }
    });
  }

  /// Corrige les caractères produits par une douchette configurée
  /// comme clavier US lorsqu'Android/Windows utilise un clavier AZERTY.
  ///
  /// Exemple : le code 0703625667039 peut arriver comme
  /// `èà\"-é(--èà\"ç` avec un mapping AZERTY de la rangée des chiffres.
  String _normalizeDouchetteCharacter(String character) {
    const azertyNumberRow = <String, String>{
      'à': '0',
      'è': '7',
      'é': '2',
      '"': '3',
      '-': '6',
      '(': '5',
      'ç': '9',
      '_': '8',
      '§': '6',
      '&': '1',
      '=': '0',
      "'": '4',
    };

    return azertyNumberRow[character] ?? character.toUpperCase();
  }

  void _onDouchetteKey(KeyEvent event) {
    if (!_douchetteMode || _searchMode || !mounted) return;
    if (event is! KeyDownEvent) return;

    // La plupart des douchettes USB/Bluetooth sont vues comme un clavier
    // et terminent le code par Entrée. On accepte aussi Tab comme suffixe.
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _submitDouchetteBarcode();
      return;
    }

    final character = event.character;
    if (character == null || character.length != 1 ||
        character.codeUnitAt(0) < 32) {
      return;
    }

    // Une douchette HID envoie des touches de clavier. Avec un clavier
    // AZERTY, la rangée numérique peut être interprétée comme èà\"-é...
    // On remet donc ces caractères dans les chiffres du code-barres.
    final normalizedCharacter = _normalizeDouchetteCharacter(character);
    _douchetteBuffer.write(normalizedCharacter);
    _douchetteInputTimer?.cancel();

    // Si le scanner n'est pas configuré avec un suffixe, le silence entre
    // deux scans finalise automatiquement le code reçu.
    _douchetteInputTimer = Timer(
      _douchetteInputTimeout,
      _submitDouchetteBarcode,
    );
  }

  void _submitDouchetteBarcode() {
    _douchetteInputTimer?.cancel();
    final barcode = _douchetteBuffer.toString().trim().toUpperCase();
    _douchetteBuffer.clear();
    if (barcode.isEmpty || !_douchetteMode || _searchMode || !mounted) {
      return;
    }

    // Une douchette est déjà séquentielle : elle envoie un code complet puis
    // passe au suivant. On ne doit PAS utiliser le verrou de la caméra ici.
    // Sinon, lorsqu'un produit n'existe pas (ou que le BLoC conserve la même
    // erreur), la douchette peut rester bloquée et ignorer les scans suivants.
    context.read<BillingBloc>().add(ScanBarcodeEvent(barcode));
    _requestDouchetteFocus();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // Verrou immédiat : le callback peut être appelé plusieurs fois avant
    // même que le premier traitement asynchrone soit terminé.
    if (_scanLocked || !mounted || !_isCameraOn || _douchetteMode || _searchMode) return;

    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (rawValue.isEmpty) return;

    final now = DateTime.now();
    final lastScan = _lastScanTimes[rawValue];
    if (lastScan != null && now.difference(lastScan) < _scanCooldown) {
      return;
    }

    _scanLocked = true;
    _lastScanTimes[rawValue] = now;
    _scanUnlockTimer?.cancel();

    try {
      // Arrêt explicite avant le traitement pour empêcher toute nouvelle
      // détection de la même étiquette pendant l'ajout au panier.
      await _scannerController.stop();

      if (mounted) {
        context.read<BillingBloc>().add(ScanBarcodeEvent(rawValue));
      }
    } catch (_) {
      _releaseScanLock();
    }
  }

  void _releaseScanLock() {
    _scanUnlockTimer?.cancel();
    if (!mounted) return;
    _scanUnlockTimer = Timer(_scanCooldown, () {
      if (mounted) {
        _scanLocked = false;
      }
    });
  }

  Future<void> _restartScanner() async {
    if (!mounted || !_isCameraOn || _douchetteMode || _searchMode) return;
    try {
      // Toujours arrêter puis redémarrer proprement le contrôleur.
      await _scannerController.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted && _isCameraOn && !_searchMode) {
        await _scannerController.start();
      }
    } catch (_) {
      // Le contrôleur peut déjà être arrêté pendant une transition de route.
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
    return KeyboardListener(
      focusNode: _douchetteFocusNode,
      autofocus: _douchetteMode && !_searchMode,
      onKeyEvent: _onDouchetteKey,
      child: Scaffold(
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
            if (!_douchetteMode) {
              await _restartScanner();
            } else {
              _requestDouchetteFocus();
            }
            // La douchette ne dépend pas du verrou de la caméra. Même en
            // cas de produit inexistant, le focus reste disponible pour le
            // prochain scan. Le verrou reste uniquement utilisé par la caméra.
            if (!_douchetteMode && _scanLocked) {
              _releaseScanLock();
            }
            return;
          }

          // Si l'état vient d'un scan, le contrôleur a déjà été stoppé.
          // On le redémarre une seule fois puis on garde un court cooldown.
          if (_scanLocked && !_douchetteMode) {
            await SystemSound.play(SystemSoundType.click);
            final last = state.cartItems.isEmpty
                ? null
                : state.cartItems.last.product.name;
            _showTopBanner(last == null
                ? 'Article ajouté au panier'
                : '$last ajouté au panier');
            await _restartScanner();
            _releaseScanLock();
          } else if (_douchetteMode) {
            // Après chaque résultat, succès ou échec, la douchette reste prête.
            _requestDouchetteFocus();
          }
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
                  _scannerController.stop();
                  await context.push('/checkout');
                  await _restartScanner();
                },
          icon: Icons.payment,
          label: 'Vérifier la vente',
        );
      }),
      ),
    );
  }

  Widget _buildScannerSection() {
    if (_searchMode) return _buildSearchSection();
    if (_douchetteMode) return _buildDouchetteSection();
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          if (!_isCameraOn) _buildCameraOffState(),

          // Menu d'actions rapides : un seul FAB pour garder l'écran propre.
          _buildQuickActionsMenu(),

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

  Widget _buildDouchetteSection() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.greenAccent, size: 48),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Douchette code-barres active',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Scannez un code-barres avec la douchette USB ou Bluetooth.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Prêt à scanner',
                    style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // Le même menu est utilisé en mode douchette pour garder une UX cohérente.
          _buildQuickActionsMenu(),
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
          IconButton(
            onPressed: () {
              setState(() {
                _searchMode = false;
                _douchetteMode = true;
                _isCameraOn = false;
              });
              _scannerController.stop();
              _requestDouchetteFocus();
            },
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Douchette',
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _searchMode = false;
                _douchetteMode = true;
                _isCameraOn = false;
              });
              _scannerController.stop();
              _requestDouchetteFocus();
            },
            icon: const Icon(Icons.close),
          ),
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
              _scannerController.start();
            },
          )
        ],
      ),
    );
  }

  Widget _buildQuickActionsMenu() {
    final top = MediaQuery.of(context).padding.top + 16;

    return Positioned(
      top: top,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: _quickActionsExpanded
                  ? _buildQuickActionsPanel()
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'quick_actions_fab',
              mini: false,
              elevation: 6,
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              tooltip: _quickActionsExpanded
                  ? 'Fermer les actions rapides'
                  : 'Actions rapides',
              onPressed: () {
                setState(() => _quickActionsExpanded = !_quickActionsExpanded);
              },
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 220),
                turns: _quickActionsExpanded ? 0.125 : 0,
                child: const Icon(Icons.add, size: 30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsPanel() {
    return Container(
      width: 235,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 1,
            offset: Offset(0, 8),
            color: Colors.black45,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildQuickActionTile(
            icon: Icons.videocam,
            label: 'Caméra',
            onPressed: _activateCameraFromQuickMenu,
          ),
          _buildQuickActionTile(
            icon: Icons.manage_search,
            label: 'Rechercher un produit',
            onPressed: _openSearchFromQuickMenu,
          ),
          _buildQuickActionTile(
            icon: Icons.assignment_return,
            label: 'Gestion des retours',
            onPressed: _openReturnsFromQuickMenu,
          ),
          _buildQuickActionTile(
            icon: Icons.history,
            label: 'Historique',
            onPressed: _openHistoryFromQuickMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _closeQuickActions() {
    if (_quickActionsExpanded && mounted) {
      setState(() => _quickActionsExpanded = false);
    }
  }

  void _activateCameraFromQuickMenu() {
    _closeQuickActions();
    setState(() {
      _searchMode = false;
      _douchetteMode = false;
      _isCameraOn = true;
    });
    _douchetteFocusNode.unfocus();
    _scannerController.start();
  }

  void _openSearchFromQuickMenu() {
    _closeQuickActions();
    setState(() => _searchMode = true);
    _scannerController.stop();
    _douchetteFocusNode.unfocus();
  }

  Future<void> _openReturnsFromQuickMenu() async {
    _closeQuickActions();
    _douchetteFocusNode.unfocus();
    _scannerController.stop();
    await context.push('/returns');
    if (!mounted) return;
    if (_douchetteMode && !_searchMode) {
      _requestDouchetteFocus();
    } else if (_isCameraOn && !_searchMode) {
      await _restartScanner();
    }
  }

  Future<void> _openHistoryFromQuickMenu() async {
    _closeQuickActions();
    _douchetteFocusNode.unfocus();
    _scannerController.stop();
    await context.push('/history');
    if (!mounted) return;
    if (_douchetteMode && !_searchMode) {
      _requestDouchetteFocus();
    } else if (_isCameraOn && !_searchMode) {
      await _restartScanner();
    }
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
