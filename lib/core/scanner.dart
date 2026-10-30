import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera view that reads the QR code on a student ID card.
/// The same card is ignored for a few seconds so one scan is not counted many times.
class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key, required this.onCode, this.paused = false});

  final void Function(String code) onCode;
  final bool paused;

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, formats: const [BarcodeFormat.qrCode]);
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (widget.paused) return;
    final code = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(seconds: 4)) return;
    _lastCode = code;
    _lastAt = now;
    widget.onCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Container(
            color: Colors.black,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: const Text('The camera could not be opened.\nAllow the camera permission for this app in phone settings.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ),
        // Aiming frame
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(28)),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
