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
    detectionTimeoutMs: 150,
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
  double _zoom = 1.5;

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
      await controller.setZoomScale(_zoom);
    } catch (_) {}
    _starting = false;
  }

  Future<void> _stop() async {
    try {
      await controller.stop();
    } catch (_) {}
  }

  Future<void> _setZoom(double value) async {
    final zoom = value.clamp(1.0, 2.0).toDouble();
    setState(() => _zoom = zoom);
    try {
      await controller.setZoomScale(zoom);
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isScanned) return;

    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;

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
              final scanWindow = Rect.fromLTWH(
                constraints.maxWidth * 0.04,
                constraints.maxHeight * 0.27,
                constraints.maxWidth * 0.92,
                constraints.maxHeight * 0.46,
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
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          Positioned(
            top: 18,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final value in [1.0, 1.5, 2.0])
                    GestureDetector(
                      onTap: () => _setZoom(value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: Text(
                          '${value.toStringAsFixed(1)}x',
                          style: TextStyle(
                            color: _zoom == value ? Colors.greenAccent : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Text(
              'Placez le code horizontalement dans le cadre. Pour un petit code, utilisez 1,5x ou 2x et évitez les reflets.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
