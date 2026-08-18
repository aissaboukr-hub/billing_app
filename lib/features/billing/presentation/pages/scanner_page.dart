import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../bloc/billing_bloc.dart';
import '../bloc/billing_event.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessingScan = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() {
          _isProcessingScan = true;
        });

        // Émission de l'événement au BLoC
        context.read<BillingBloc>().add(ScanBarcodeEvent(rawValue));

        // Signal visuel court
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code scanné : $rawValue'),
            duration: const Duration(milliseconds: 800),
          ),
        );

        // Pause de sécurité pour éviter les scans multiples répétés
        await Future.delayed(const Duration(milliseconds: 1500));

        if (mounted) {
          setState(() {
            _isProcessingScan = false;
          });
        }
        break;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un article'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller.torchState,
              builder: (context, state, child) {
                switch (state) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                }
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller.cameraFacingState,
              builder: (context, state, child) {
                return const Icon(Icons.cameraswitch);
              },
            ),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Container(
            decoration: ShapeDecoration(
              shape: QrScannerOverlayShape(
                borderColor: Theme.of(context).primaryColor,
                borderRadius: 12,
                borderLength: 30,
                borderWidth: 8,
                cutOutSize: MediaQuery.of(context).size.width * 0.75,
              ),
            ),
          ),
          if (_isProcessingScan)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.blue,
    this.borderWidth = 8.0,
    this.borderRadius = 12.0,
    this.borderLength = 30.0,
    this.cutOutSize = 250.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final width = rect.width;
    final height = rect.height;
    final boxRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    final backgroundPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final cutOutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          boxRect,
          Radius.circular(borderRadius),
        ),
      );

    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, width, height));

    canvas.drawPath(
      Path.combine(PathOperation.difference, backgroundPath, cutOutPath),
      backgroundPaint,
    );

    final path = Path();
    path.moveTo(boxRect.left, boxRect.top + borderLength);
    path.lineTo(boxRect.left, boxRect.top + borderRadius);
    path.arcToPoint(
      Offset(boxRect.left + borderRadius, boxRect.top),
      radius: Radius.circular(borderRadius),
    );
    path.lineTo(boxRect.left + borderLength, boxRect.top);

    path.moveTo(boxRect.right - borderLength, boxRect.top);
    path.lineTo(boxRect.right - borderRadius, boxRect.top);
    path.arcToPoint(
      Offset(boxRect.right, boxRect.top + borderRadius),
      radius: Radius.circular(borderRadius),
    );
    path.lineTo(boxRect.right, boxRect.top + borderLength);

    path.moveTo(boxRect.right, boxRect.bottom - borderLength);
    path.lineTo(boxRect.right, boxRect.bottom - borderRadius);
    path.arcToPoint(
      Offset(boxRect.right - borderRadius, boxRect.bottom),
      radius: Radius.circular(borderRadius),
    );
    path.lineTo(boxRect.right - borderLength, boxRect.bottom);

    path.moveTo(boxRect.left + borderLength, boxRect.bottom);
    path.lineTo(boxRect.left + borderRadius, boxRect.bottom);
    path.arcToPoint(
      Offset(boxRect.left, boxRect.bottom - borderRadius),
      radius: Radius.circular(borderRadius),
    );
    path.lineTo(boxRect.left, boxRect.bottom - borderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) => this;
}
