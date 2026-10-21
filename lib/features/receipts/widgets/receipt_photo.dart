import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/features/receipts/services/receipt_scanner.dart';

/// Zeigt ein Belegfoto aus dem [ReceiptImageStore] (relativer oder alter absoluter Pfad).
/// Fehlt die Datei, wird [placeholder] gezeigt.
class ReceiptPhoto extends StatefulWidget {
  final String? path;
  final double? width;
  final double? height;
  final Widget placeholder;
  const ReceiptPhoto({super.key, required this.path, this.width, this.height, this.placeholder = const SizedBox.shrink()});

  @override
  State<ReceiptPhoto> createState() => _ReceiptPhotoState();
}

class _ReceiptPhotoState extends State<ReceiptPhoto> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ReceiptPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.path;
    final f = await context.read<ReceiptImageStore>().resolve(path);
    if (mounted && path == widget.path) setState(() => _file = f);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.path == null ? null : _file;
    if (file == null) return widget.placeholder;
    return Image.file(
      file,
      key: ValueKey(file.path),
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      // Datei inzwischen gelöscht oder kaputt → Platzhalter statt Fehlerbild
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
  }
}
