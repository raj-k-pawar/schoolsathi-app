import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Opens Razorpay checkout (UPI, cards, net banking).
/// Returns the signed result to verify with our server, or null if the parent closed it.
Future<Map<String, String>?> openCheckout({
  required String keyId,
  required String orderId,
  required int amountPaise,
  required String schoolName,
  required String description,
  String? contact,
}) {
  final completer = Completer<Map<String, String>?>();
  final razorpay = Razorpay();

  void finish(Map<String, String>? result, [Object? error]) {
    if (completer.isCompleted) return;
    razorpay.clear();
    error == null ? completer.complete(result) : completer.completeError(error);
  }

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
    finish({
      'razorpay_order_id': response.orderId ?? orderId,
      'razorpay_payment_id': response.paymentId ?? '',
      'razorpay_signature': response.signature ?? '',
    });
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
    // Code 2 is "payment cancelled by user".
    response.code == Razorpay.PAYMENT_CANCELLED ? finish(null) : finish(null, StateError(response.message ?? 'Payment failed'));
  });
  razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) => finish(null));

  razorpay.open({
    'key': keyId,
    'order_id': orderId,
    'amount': amountPaise,
    'currency': 'INR',
    'name': schoolName,
    'description': description,
    if (contact != null) 'prefill': {'contact': contact},
    'retry': {'enabled': true, 'max_count': 1},
  });

  return completer.future;
}
