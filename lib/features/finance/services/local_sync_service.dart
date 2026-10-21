import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/finance/services/export_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LocalSyncService {
  LocalSyncService({required DatabaseService db, required ExportService exportService, http.Client? client})
      : _db = db,
        _exportService = exportService,
        _client = client ?? http.Client();

  final DatabaseService _db;
  final ExportService _exportService;
  final http.Client _client;

  Future<void> exportData(int userId) async {
    final jsonString = await _exportService.generateJson(userId);
    
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/lifehub_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonString);

    await Share.shareXFiles([XFile(file.path)], text: 'LifeHub Backup von ${DateTime.now()}');
  }

  /// Wiederherstellung aus einem JSON-Backup ist noch nicht implementiert. Bisher meldete
  /// die App hier Erfolg, ohne etwas zu importieren – jetzt schlägt der Aufruf sichtbar fehl.
  Future<bool> importData(int userId) async {
    throw UnsupportedError('Das Wiederherstellen aus einem JSON-Backup wird noch nicht unterstützt.');
  }

  Future<bool> syncToIP(int userId, String ip) async {
    try {
      final db = await _db.database;
      
      // 1. Check for existing session
      final List<Map<String, dynamic>> sessions = await db.query(
        'sync_sessions',
        where: 'target_device_id = ? AND userid = ?',
        whereArgs: [ip, userId],
      );
      // Vor dem Export merken: was während des Sendens geändert wird, kommt beim nächsten Mal mit
      final startedAt = syncStamp();

      String payload;
      DateTime? lastSync;
      
      if (sessions.isNotEmpty) {
        lastSync = DateTime.parse(sessions.first['last_sync_timestamp']);
        debugPrint('[*] Found existing session for $ip. Last sync: $lastSync');
        payload = await _exportService.generateChangeset(userId, lastSync);
      } else {
        debugPrint('[*] No previous session for $ip. Performing full sync.');
        payload = await _exportService.generateJson(userId);
      }

      final response = await _client.post(
        Uri.parse('http://$ip:8000/sync'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // 2. Update session timestamp
        if (sessions.isNotEmpty) {
          await db.update(
            'sync_sessions',
            {'last_sync_timestamp': startedAt, 'status': 'success'},
            where: 'id = ?',
            whereArgs: [sessions.first['id']],
          );
        } else {
          await db.insert('sync_sessions', {
            'target_device_id': ip,
            'userid': userId,
            'last_sync_timestamp': startedAt,
            'status': 'success',
          });
        }
        return true;
      } else {
        debugPrint('[!] Sync failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[!] Sync Error: $e');
      return false;
    }
  }

  Future<bool> checkServerStatus(String ip) async {
    try {
      final response = await _client.get(Uri.parse('http://$ip:8000/status')).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
