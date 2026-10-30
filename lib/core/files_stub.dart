import 'dart:typed_data';

/// Web build (used only for previewing the UI): files cannot be opened.
Future<bool> saveAndOpen(Uint8List bytes, String fileName) async => false;
