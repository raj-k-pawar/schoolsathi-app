/// Web build (used only for previewing the UI): no payment screen.
Future<Map<String, String>?> openCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String schoolName,
  required String description,
  String? contact,
}) async {
  throw UnsupportedError('Online payment works only in the Android app.');
}
