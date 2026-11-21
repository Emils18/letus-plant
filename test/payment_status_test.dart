import 'package:flutter_test/flutter_test.dart';
import 'package:letus_plant/models/payment_status.dart';

void main() {
  test('keeps historical payment methods separate from payment status', () {
    expect(paymentStatusLabel('To be agreed in person'), 'Unpaid');
    expect(paymentStatusLabel('Cash on Delivery', 'Cash on Delivery'), 'Unpaid');
    expect(paymentStatusLabel(' paid '), 'Paid');
    expect(paymentStatusLabel('Refunded'), 'Refunded');
  });
}
