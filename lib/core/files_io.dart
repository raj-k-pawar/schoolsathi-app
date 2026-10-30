import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a downloaded file (receipt PDF, attachment) on the phone and opens it.
Future<bool> saveAndOpen(Uint8List bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path);
  return result.type == ResultType.done;
}
