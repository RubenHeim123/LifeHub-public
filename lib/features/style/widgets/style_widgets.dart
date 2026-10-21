import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/services/image_store.dart';
import 'package:frontend/core/ui/theme.dart';

/// Wählt ein Foto aus und legt es in der Inventar-Bildablage ab. Liefert den gespeicherten Pfad.
Future<String?> pickStyleImage(BuildContext context) async {
  final images = context.read<InventoryImageStore>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return null;
    return await images.importFile(path);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Bild konnte nicht übernommen werden: ${errorText(e)}')));
    return null;
  }
}

/// Zeigt ein gespeichertes Foto (Inventar-Bildablage) oder ersatzweise ein Icon.
class StoredImage extends StatefulWidget {
  final String? path;
  final IconData fallback;
  final double? size;
  final double radius;
  const StoredImage({super.key, required this.path, required this.fallback, this.size, this.radius = 12});

  @override
  State<StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends State<StoredImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(StoredImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  Future<void> _resolve() async {
    final f = await context.read<InventoryImageStore>().resolve(widget.path);
    if (mounted) setState(() => _file = f);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final file = widget.path == null ? null : _file;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: file != null
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: c.cardAlt,
                child: Center(child: Icon(widget.fallback, color: c.muted, size: (widget.size ?? 64) * 0.45)),
              ),
      ),
    );
  }
}
