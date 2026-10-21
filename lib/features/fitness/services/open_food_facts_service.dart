import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:frontend/features/fitness/models/nutrition.dart';

/// Holt Produktdaten zu einem Barcode aus der freien Datenbank Open Food Facts.
class OpenFoodFactsService {
  OpenFoodFactsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _fields = 'product_name,product_name_de,brands,nutriments,serving_quantity,product_quantity';

  /// Liefert ein (noch nicht gespeichertes) Lebensmittel oder `null`, wenn das Produkt
  /// unbekannt ist. Netzwerkfehler werfen eine [OpenFoodFactsException].
  Future<Food?> lookup(String barcode, {required int userid}) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode.json', {'fields': _fields});
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': 'LifeHub/1.0 (private app)'})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw OpenFoodFactsException('Keine Verbindung zu Open Food Facts: $e');
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw OpenFoodFactsException('Open Food Facts antwortet mit Status ${response.statusCode}');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (body['status'] != 1 || body['product'] is! Map) return null;
    final p = (body['product'] as Map).cast<String, dynamic>();
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    double v(String key) {
      final raw = n[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse('${raw ?? ''}') ?? 0;
    }

    final name = [p['product_name_de'], p['product_name']]
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (name.isEmpty) return null;
    final brand = (p['brands'] as String?)?.split(',').first.trim();
    final serving = p['serving_quantity'];
    final pack = p['product_quantity'];
    final packSize = pack is num ? pack.toDouble() : double.tryParse('${pack ?? ''}');

    return Food(
      userid: userid,
      name: name,
      brand: brand == null || brand.isEmpty ? null : brand,
      barcode: barcode,
      per100: Macros(
        kcal: v('energy-kcal_100g'),
        protein: v('proteins_100g'),
        carbs: v('carbohydrates_100g'),
        fat: v('fat_100g'),
      ),
      servingGrams: serving is num ? serving.toDouble() : double.tryParse('${serving ?? ''}'),
      packSizes: packSize == null || packSize <= 0 ? const [] : [packSize],
    );
  }
}

class OpenFoodFactsException implements Exception {
  final String message;
  OpenFoodFactsException(this.message);

  @override
  String toString() => message;
}
