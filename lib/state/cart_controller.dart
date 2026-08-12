import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/sales_repository.dart';

class CartState {
  const CartState({
    this.lines = const [],
    this.paymentType = PaymentType.cash,
    this.customerId,
    this.customerName,
    this.note,
  });

  final List<CartLine> lines;
  final PaymentType paymentType;
  final int? customerId;
  final String? customerName;
  final String? note;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  int get totalCentavos =>
      lines.fold(0, (sum, line) => sum + line.lineTotalCentavos);

  int get itemCount => lines.fold(0, (sum, line) => sum + line.qty);

  int qtyOf(int? productId) {
    if (productId == null) return 0;
    for (final line in lines) {
      if (line.product.id == productId) return line.qty;
    }
    return 0;
  }

  /// A credit sale is only valid once a customer has been chosen -- otherwise
  /// the debt has no one attached to it.
  bool get canCheckout =>
      isNotEmpty && (paymentType != PaymentType.credit || customerId != null);

  CartState copyWith({
    List<CartLine>? lines,
    PaymentType? paymentType,
    int? customerId,
    String? customerName,
    bool clearCustomer = false,
    String? note,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      paymentType: paymentType ?? this.paymentType,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName:
          clearCustomer ? null : (customerName ?? this.customerName),
      note: note ?? this.note,
    );
  }
}

/// The running basket on the Sell screen. Held in memory only -- an
/// unfinished sale is not worth persisting, and clearing it is the fastest way
/// to recover from a mis-tap.
class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  void add(Product product, {int qty = 1}) {
    if (product.id == null) return;

    final index =
        state.lines.indexWhere((line) => line.product.id == product.id);
    final next = [...state.lines];

    if (index >= 0) {
      next[index] = next[index].withQty(next[index].qty + qty);
    } else {
      next.add(CartLine(product: product, qty: qty));
    }
    state = state.copyWith(lines: next);
  }

  void setQty(int productId, int qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }
    final next = [
      for (final line in state.lines)
        if (line.product.id == productId) line.withQty(qty) else line,
    ];
    state = state.copyWith(lines: next);
  }

  void increment(int productId) {
    final current = state.qtyOf(productId);
    setQty(productId, current + 1);
  }

  void decrement(int productId) {
    final current = state.qtyOf(productId);
    setQty(productId, current - 1);
  }

  void remove(int productId) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.product.id != productId).toList(),
    );
  }

  void setPaymentType(PaymentType type) {
    if (type == PaymentType.credit) {
      state = state.copyWith(paymentType: type);
    } else {
      // Dropping out of credit clears the customer so a stale name cannot ride
      // along on a cash sale.
      state = state.copyWith(paymentType: type, clearCustomer: true);
    }
  }

  void setCustomer(int? id, String? name) {
    if (id == null) {
      state = state.copyWith(clearCustomer: true);
    } else {
      state = state.copyWith(customerId: id, customerName: name);
    }
  }

  void setNote(String? note) => state = state.copyWith(note: note);

  void clear() => state = const CartState();
}

final cartProvider =
    StateNotifierProvider<CartController, CartState>((ref) => CartController());
