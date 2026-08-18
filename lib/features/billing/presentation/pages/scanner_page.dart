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
  bool _torchEnabled = false;
  bool _usingFrontCamera = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessingScan) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        setState(() => _isProcessingScan = true);
        context.read<BillingBloc>().add(ScanBarcodeEvent(rawValue));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code scanné : $rawValue'),
            duration: const Duration(milliseconds: 800),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) setState(() => _isProcessingScan = false);
        break;
      }
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchEnabled = !_torchEnabled);
  }

  Future<void> _switchCamera() async {
    await _controller.switchCamera();
    if (mounted) setState(() => _usingFrontCamera = !_usingFrontCamera);
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
            icon: Icon(
              _torchEnabled ? Icons.flash_on : Icons.flash_off,
              color: _torchEnabled ? Colors.yellow : Colors.grey,
            ),
            onPressed: _toggleTorch,
          ),
          IconButton(
            icon: Icon(
              _usingFrontCamera
                  ? Icons.camera_front
                  : Icons.camera_rear,
            ),
            onPressed: _switchCamera,
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
            const Center(child: CircularProgressIndicator()),
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

    final fullPath = Path()..addRect(rect);
    final overlayPath = Path.combine(
      PathOperation.difference,
      fullPath,
      cutOutPath,
    );
    canvas.drawPath(overlayPath, backgroundPaint);

    final left = boxRect.left;
    final right = boxRect.right;
    final top = boxRect.top;
    final bottom = boxRect.bottom;
    final r = borderRadius;
    final l = borderLength;

    canvas.drawLine(Offset(left, top + l), Offset(left, top + r), borderPaint);
    canvas.drawLine(Offset(left + r, top), Offset(left + l, top), borderPaint);
    canvas.drawLine(Offset(right - l, top), Offset(right - r, top), borderPaint);
    canvas.drawLine(Offset(right, top + r), Offset(right, top + l), borderPaint);
    canvas.drawLine(Offset(left, bottom - l), Offset(left, bottom - r), borderPaint);
    canvas.drawLine(Offset(left + r, bottom), Offset(left + l, bottom), borderPaint);
    canvas.drawLine(Offset(right - l, bottom), Offset(right - r, bottom), borderPaint);
    canvas.drawLine(Offset(right, bottom - r), Offset(right, bottom - l), borderPaint);
  }

  @override
  ShapeBorder scale(double t) => QrScannerOverlayShape(
        borderColor: borderColor,
        borderWidth: borderWidth * t,
        borderRadius: borderRadius * t,
        borderLength: borderLength * t,
        cutOutSize: cutOutSize * t,
      );
}
