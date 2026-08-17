import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final MobileScannerController controller = MobileScannerController(
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

  bool _isScanned = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted && !_isScanned) {
        Future<void>.delayed(const Duration(milliseconds: 300), _start);
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stop();
    }
  }

  Future<void> _start() async {
    if (!mounted || _isScanned || _starting) return;
    _starting = true;
    try {
      await controller.start();
    } catch (_) {}
    _starting = false;
  }

  Future<void> _stop() async {
    try {
      await controller.stop();
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isScanned) return;

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
    final value = bestBarcode?.rawValue?.trim();
    if (value == null || value.isEmpty) return;

    _isScanned = true;
    await _stop();
    await SystemSound.play(SystemSoundType.click);
    if (mounted) context.pop(value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.stop();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.chevron_left, size: 28, color: Theme.of(context).primaryColor),
          onPressed: () async {
            await _stop();
            if (mounted) context.pop();
          },
        ),
        title: const Text(
          'Scanner un code-barres',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Zone large et horizontale : les petits codes 1D sur des
              // surfaces cylindriques ont besoin de plus de largeur et
              // d'une hauteur suffisante pour conserver toutes les barres.
              final scanWindow = Rect.fromLTWH(
                constraints.maxWidth * 0.02,
                constraints.maxHeight * 0.33,
                constraints.maxWidth * 0.96,
                constraints.maxHeight * 0.34,
              );
              return MobileScanner(
                controller: controller,
                onDetect: _onDetect,
                fit: BoxFit.cover,
                scanWindow: scanWindow,
              );
            },
          ),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Text(
              'Placez le code horizontalement dans le cadre. Gardez l\'objet immobile, à bonne distance, et évitez les reflets directs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
