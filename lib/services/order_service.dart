import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class CheckoutResult {
  final bool success;
  final String? error;
  final int orderCount;

  const CheckoutResult({
    required this.success,
    this.error,
    this.orderCount = 0,
  });
}

class ProofUploadResult {
  final bool success;
  final String? error;
  final String? imageUrl;

  const ProofUploadResult({
    required this.success,
    this.error,
    this.imageUrl,
  });
}

class OrderService {
  final SupabaseClient supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  Future<List<Map<String, dynamic>>> getBuyerOrders() async {
    final user = supabase.auth.currentUser;

    if (user == null) return [];

    try {
      final data = await supabase
          .from('orders')
          .select('''
            *,
            order_items(
              *,
              products(
                id,
                name,
                image_url,
                image,
                farmer_id,
                farmer,
                farmer_name
              )
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      print('getBuyerOrders database error: ${e.message}');
      return [];
    } catch (e) {
      print('getBuyerOrders error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFarmerOrders() async {
    final user = supabase.auth.currentUser;

    if (user == null) return [];

    try {
      final data = await supabase
          .from('orders')
          .select('''
            *,
            order_items(
              *,
              products(
                id,
                name,
                image_url,
                image,
                farmer_id,
                farmer,
                farmer_name
              )
            )
          ''')
          .eq('farmer_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      print('getFarmerOrders database error: ${e.message}');
      return [];
    } catch (e) {
      print('getFarmerOrders error: $e');
      return [];
    }
  }

  Future<CheckoutResult> checkoutCart({
    required List<Map<String, dynamic>> cartItems,
    required String shippingName,
    required String shippingPhone,
    required String shippingAddress,
    required String paymentMethod,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const CheckoutResult(
        success: false,
        error: 'Please login before checkout.',
      );
    }

    if (cartItems.isEmpty) {
      return const CheckoutResult(
        success: false,
        error: 'Your cart is empty.',
      );
    }

    final cleanName = shippingName.trim();
    final cleanPhone = shippingPhone.trim();
    final cleanAddress = shippingAddress.trim();
    final cleanPayment = paymentMethod.trim().isEmpty
        ? 'Cash on Delivery'
        : paymentMethod.trim();

    if (cleanName.isEmpty || cleanPhone.isEmpty || cleanAddress.isEmpty) {
      return const CheckoutResult(
        success: false,
        error: 'Please complete shipping details.',
      );
    }

    try {
      final groupedByFarmer = <String, List<Map<String, dynamic>>>{};

      for (final item in cartItems) {
        final farmerId = item['farmer_id']?.toString().trim();

        if (farmerId == null || farmerId.isEmpty) {
          return CheckoutResult(
            success: false,
            error:
                'Product "${item['name'] ?? 'Unknown'}" has no farmer owner.',
          );
        }

        groupedByFarmer.putIfAbsent(farmerId, () => []);
        groupedByFarmer[farmerId]!.add(item);
      }

      int createdOrders = 0;

      for (final entry in groupedByFarmer.entries) {
        final farmerId = entry.key;
        final items = entry.value;

        final totalAmount = items.fold<double>(0, (sum, item) {
          final price = _toDouble(item['price']);
          final quantity = _toInt(item['quantity']);
          return sum + (price * quantity);
        });

        final insertedOrder = await supabase
            .from('orders')
            .insert({
              'order_code': _generateOrderCode(),
              'user_id': user.id,
              'farmer_id': farmerId,
              'email': user.email,
              'status': 'Pending',
              'shipping_name': cleanName,
              'shipping_phone': cleanPhone,
              'shipping_address': cleanAddress,
              'city': 'Cebu City',
              'postal_code': '6000',
              'payment_method': cleanPayment,
              'payment_status': cleanPayment.toLowerCase().contains('cash')
                  ? 'Unpaid'
                  : 'Pending Verification',
              'delivery_method': 'Delivery',
              'delivery_status': 'Pending',
              'total_amount': totalAmount,
              'confirmed_received': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();

        final orderId = insertedOrder['id'].toString();

        final orderItems = items.map((item) {
          final price = _toDouble(item['price']);
          final quantity = _toInt(item['quantity']);
          final productName =
              item['name']?.toString().trim().isNotEmpty == true
                  ? item['name'].toString().trim()
                  : 'Lettuce Product';

          return {
            'order_id': orderId,
            'product_id': item['id'],
            'product_name': productName,
            'quantity': quantity,
            'price': price,
            'price_at_time': price,
            'subtotal': price * quantity,
          };
        }).toList();

        await supabase.from('order_items').insert(orderItems);

        final notificationError = await _notificationService.createNotification(
          userId: farmerId,
          orderId: orderId,
          title: 'New Order',
          message: 'Someone ordered your product.',
          type: 'new_order',
        );

        if (notificationError != null) {
          print('CREATE NOTIFICATION FAILED: $notificationError');
        } else {
          print('NOTIFICATION CREATED FOR FARMER: $farmerId');
        }

        createdOrders++;
      }

      return CheckoutResult(
        success: true,
        orderCount: createdOrders,
      );
    } on PostgrestException catch (e) {
      return CheckoutResult(
        success: false,
        error: 'Database error: ${e.message}',
      );
    } catch (e) {
      return CheckoutResult(
        success: false,
        error: 'Checkout error: $e',
      );
    }
  }

  Future<String?> confirmReceived(String orderId) async {
    final user = supabase.auth.currentUser;

    if (user == null) return 'Please login first.';

    try {
      final orderData = await supabase
          .from('orders')
          .select('farmer_id, order_code')
          .eq('id', orderId)
          .eq('user_id', user.id)
          .single();

      await supabase
          .from('orders')
          .update({
            'status': 'Completed',
            'delivery_status': 'Received',
            'payment_status': 'Paid',
            'confirmed_received': true,
            'received_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('user_id', user.id);

      final farmerId = orderData['farmer_id']?.toString();
      final orderCode = orderData['order_code']?.toString() ?? orderId;

      if (farmerId != null && farmerId.isNotEmpty) {
        final notificationError =
            await _notificationService.createNotification(
          userId: farmerId,
          orderId: orderId,
          title: 'Order Received',
          message: 'The buyer confirmed receiving order $orderCode.',
          type: 'confirm_received',
        );

        if (notificationError != null) {
          print('CREATE CONFIRM RECEIVED NOTIFICATION FAILED: $notificationError');
        }
      }

      return null;
    } on PostgrestException catch (e) {
      return 'Database error: ${e.message}';
    } catch (e) {
      return 'Confirm received error: $e';
    }
  }

  Future<String?> updateFarmerOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) return 'Please login first.';

    try {
      final orderData = await supabase
          .from('orders')
          .select('user_id, order_code')
          .eq('id', orderId)
          .eq('farmer_id', user.id)
          .single();

      await supabase
          .from('orders')
          .update({
            'status': status,
            'delivery_status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('farmer_id', user.id);

      final buyerId = orderData['user_id']?.toString();
      final orderCode = orderData['order_code']?.toString() ?? orderId;

      if (buyerId != null && buyerId.isNotEmpty) {
        final notificationError =
            await _notificationService.createNotification(
          userId: buyerId,
          orderId: orderId,
          title: 'Order Update',
          message: 'Your order $orderCode is now $status.',
          type: 'delivery_update',
        );

        if (notificationError != null) {
          print('CREATE ORDER UPDATE NOTIFICATION FAILED: $notificationError');
        }
      }

      return null;
    } on PostgrestException catch (e) {
      return 'Database error: ${e.message}';
    } catch (e) {
      return 'Order update error: $e';
    }
  }

  Future<ProofUploadResult> submitDeliveryProof({
    required String orderId,
    required XFile proofImage,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const ProofUploadResult(
        success: false,
        error: 'Please login first.',
      );
    }

    try {
      final bytes = await proofImage.readAsBytes();
      final extension = _extensionFromName(proofImage.name);
      final path =
          '${user.id}/$orderId-${DateTime.now().millisecondsSinceEpoch}.$extension';

      await supabase.storage.from('delivery-proofs').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentType(extension),
            ),
          );

      final imageUrl = supabase.storage
          .from('delivery-proofs')
          .getPublicUrl(path);

      await supabase
          .from('orders')
          .update({
            'proof_image_url': imageUrl,
            'delivery_proof_url': imageUrl,
            'status': 'Delivered',
            'delivery_status': 'Delivered',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId)
          .eq('farmer_id', user.id);

      final orderData = await supabase
          .from('orders')
          .select('user_id, order_code')
          .eq('id', orderId)
          .eq('farmer_id', user.id)
          .single();

      final buyerId = orderData['user_id']?.toString();
      final orderCode = orderData['order_code']?.toString() ?? orderId;

      if (buyerId != null && buyerId.isNotEmpty) {
        final notificationError =
            await _notificationService.createNotification(
          userId: buyerId,
          orderId: orderId,
          title: 'Order Delivered',
          message: 'Your order $orderCode has been marked as delivered.',
          type: 'delivery_update',
        );

        if (notificationError != null) {
          print('CREATE DELIVERED NOTIFICATION FAILED: $notificationError');
        }
      }

      return ProofUploadResult(
        success: true,
        imageUrl: imageUrl,
      );
    } on StorageException catch (e) {
      return ProofUploadResult(
        success: false,
        error: 'Storage error: ${e.message}',
      );
    } on PostgrestException catch (e) {
      return ProofUploadResult(
        success: false,
        error: 'Database error: ${e.message}',
      );
    } catch (e) {
      return ProofUploadResult(
        success: false,
        error: 'Proof upload error: $e',
      );
    }
  }

  String _generateOrderCode() {
    final now = DateTime.now();
    return 'ORD-${now.year}${_two(now.month)}${_two(now.day)}-${now.millisecondsSinceEpoch.toString().substring(8)}';
  }

  String _two(int value) {
    return value.toString().padLeft(2, '0');
  }

  String _extensionFromName(String name) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.jpeg')) return 'jpeg';

    return 'jpg';
  }

  String _contentType(String extension) {
    if (extension == 'png') return 'image/png';
    if (extension == 'webp') return 'image/webp';
    if (extension == 'jpeg') return 'image/jpeg';

    return 'image/jpeg';
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();

    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;

    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }
}