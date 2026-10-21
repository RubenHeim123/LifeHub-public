import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/fitness/repositories/nutrition_repository.dart';
import 'package:frontend/features/fitness/services/open_food_facts_service.dart';

/// Öffnet die Kamera und liefert den gescannten Barcode (oder `null` bei Abbruch).
/// In Tests wird eine eigene Implementierung per Provider eingesetzt.
class BarcodeScanner {
  const BarcodeScanner();

  Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _BarcodeScanScreen()));
}

class _BarcodeScanScreen extends StatefulWidget {
  const _BarcodeScanScreen();

  @override
  State<_BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<_BarcodeScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode scannen')),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (code == null || _done) return;
            _done = true;
            Navigator.of(context).pop(code);
          },
          errorBuilder: (context, error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Kamera nicht verfügbar: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Barcode in den Rahmen halten', style: TextStyle(color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

/// Sucht einen Barcode zuerst in den eigenen Lebensmitteln, sonst bei Open Food Facts,
/// und speichert neue Treffer als eigenes Lebensmittel (damit der nächste Scan offline klappt).
class FoodLookupService {
  FoodLookupService({required NutritionRepository nutrition, required OpenFoodFactsService openFoodFacts})
      : _nutrition = nutrition,
        _off = openFoodFacts;

  final NutritionRepository _nutrition;
  final OpenFoodFactsService _off;

  /// `null`, wenn das Produkt nirgends bekannt ist. Wirft [OpenFoodFactsException] bei Netzproblemen.
  Future<Food?> byBarcode(int uid, String barcode) async {
    final own = await _nutrition.findByBarcode(uid, barcode);
    if (own != null) return own;
    final remote = await _off.lookup(barcode, userid: uid);
    if (remote == null) return null;
    return _nutrition.saveFood(remote);
  }
}
