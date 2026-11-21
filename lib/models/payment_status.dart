String paymentStatusLabel(Object? status, [Object? paymentMethod]) {
  final value = status?.toString().trim() ?? '';
  final normalized = value.toLowerCase();
  if (normalized == 'paid') return 'Paid';
  if (value.isEmpty ||
      normalized == 'unpaid' ||
      normalized == 'to be agreed in person' ||
      normalized == paymentMethod?.toString().trim().toLowerCase()) {
    return 'Unpaid';
  }
  return value;
}
