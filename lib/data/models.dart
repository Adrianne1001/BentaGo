import '../core/format.dart';

enum PaymentType { cash, utang, gcash }

extension PaymentTypeX on PaymentType {
  String get code => name;

  String get label => switch (this) {
        PaymentType.cash => 'Cash',
        PaymentType.utang => 'Utang',
        PaymentType.gcash => 'GCash',
      };

  static PaymentType fromCode(String? code) => switch (code) {
        'utang' => PaymentType.utang,
        'gcash' => PaymentType.gcash,
        _ => PaymentType.cash,
      };
}

enum StockReason { restock, sale, spoilage, personal, correction }

extension StockReasonX on StockReason {
  String get code => name;

  String get label => switch (this) {
        StockReason.restock => 'Delivery',
        StockReason.sale => 'Nabenta',
        StockReason.spoilage => 'Sira / expired',
        StockReason.personal => 'Kinuha sa bahay',
        StockReason.correction => 'Pagwawasto',
      };

  static StockReason fromCode(String? code) => switch (code) {
        'sale' => StockReason.sale,
        'spoilage' => StockReason.spoilage,
        'personal' => StockReason.personal,
        'correction' => StockReason.correction,
        _ => StockReason.restock,
      };
}

/// A single sellable item. Sold by the piece only -- one product, one unit.
/// Only [name] and [priceCentavos] are required; every other field may be
/// blank, and the UI degrades gracefully when they are.
class Product {
  const Product({
    this.id,
    required this.name,
    required this.priceCentavos,
    this.costCentavos = 0,
    this.description,
    this.category,
    this.emoji,
    this.barcode,
    this.unitLabel = 'pc',
    this.stock = 0,
    this.reorderLevel = 0,
    this.trackStock = true,
    this.archived = false,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String name;
  final int priceCentavos;
  final int costCentavos;
  final String? description;
  final String? category;
  final String? emoji;
  final String? barcode;
  final String unitLabel;
  final int stock;
  final int reorderLevel;
  final bool trackStock;
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Peso margin on one piece. Zero when no cost has been entered, which is
  /// fine -- profit reporting simply treats those items as pure revenue and
  /// the reports screen says so.
  int get marginCentavos => priceCentavos - costCentavos;

  bool get hasCost => costCentavos > 0;

  double? get marginPercent {
    if (priceCentavos <= 0 || !hasCost) return null;
    return marginCentavos / priceCentavos * 100;
  }

  bool get isLowStock =>
      trackStock && reorderLevel > 0 && stock <= reorderLevel;

  bool get isOutOfStock => trackStock && stock <= 0;

  /// The letter shown on the tile when no emoji was chosen.
  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  factory Product.fromRow(Map<String, Object?> row) => Product(
        id: row['id'] as int?,
        name: row['name'] as String? ?? '',
        priceCentavos: (row['price_centavos'] as int?) ?? 0,
        costCentavos: (row['cost_centavos'] as int?) ?? 0,
        description: row['description'] as String?,
        category: row['category'] as String?,
        emoji: row['emoji'] as String?,
        barcode: row['barcode'] as String?,
        unitLabel: (row['unit_label'] as String?)?.trim().isNotEmpty == true
            ? row['unit_label'] as String
            : 'pc',
        stock: (row['stock'] as int?) ?? 0,
        reorderLevel: (row['reorder_level'] as int?) ?? 0,
        trackStock: ((row['track_stock'] as int?) ?? 1) == 1,
        archived: ((row['archived'] as int?) ?? 0) == 1,
        createdAt: row['created_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: row['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  Map<String, Object?> toRow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'price_centavos': priceCentavos,
      'cost_centavos': costCentavos,
      'description': _blankToNull(description),
      'category': _blankToNull(category),
      'emoji': _blankToNull(emoji),
      'barcode': _blankToNull(barcode),
      'unit_label': unitLabel.trim().isEmpty ? 'pc' : unitLabel.trim(),
      'stock': stock,
      'reorder_level': reorderLevel,
      'track_stock': trackStock ? 1 : 0,
      'archived': archived ? 1 : 0,
      'created_at': createdAt?.millisecondsSinceEpoch ?? now,
      'updated_at': now,
    };
  }

  Product copyWith({
    int? id,
    String? name,
    int? priceCentavos,
    int? costCentavos,
    String? description,
    String? category,
    String? emoji,
    String? barcode,
    String? unitLabel,
    int? stock,
    int? reorderLevel,
    bool? trackStock,
    bool? archived,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      priceCentavos: priceCentavos ?? this.priceCentavos,
      costCentavos: costCentavos ?? this.costCentavos,
      description: description ?? this.description,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      barcode: barcode ?? this.barcode,
      unitLabel: unitLabel ?? this.unitLabel,
      stock: stock ?? this.stock,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      trackStock: trackStock ?? this.trackStock,
      archived: archived ?? this.archived,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class Customer {
  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.note,
    this.archived = false,
    this.createdAt,
    this.balanceCentavos = 0,
    this.lastActivity,
  });

  final int? id;
  final String name;
  final String? phone;
  final String? note;
  final bool archived;
  final DateTime? createdAt;

  /// Derived from the ledger, never stored on the row -- a balance column and
  /// a ledger will drift apart eventually, and the ledger is the truth.
  final int balanceCentavos;
  final DateTime? lastActivity;

  bool get owes => balanceCentavos > 0;

  String get initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  int get daysSinceActivity => lastActivity == null
      ? 0
      : DateTime.now().difference(lastActivity!).inDays;

  factory Customer.fromRow(Map<String, Object?> row) => Customer(
        id: row['id'] as int?,
        name: row['name'] as String? ?? '',
        phone: row['phone'] as String?,
        note: row['note'] as String?,
        archived: ((row['archived'] as int?) ?? 0) == 1,
        createdAt: row['created_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        balanceCentavos: (row['balance_centavos'] as int?) ?? 0,
        lastActivity: row['last_activity'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['last_activity'] as int),
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'name': name.trim(),
        'phone': _blankToNull(phone),
        'note': _blankToNull(note),
        'archived': archived ? 1 : 0,
        'created_at':
            createdAt?.millisecondsSinceEpoch ??
                DateTime.now().millisecondsSinceEpoch,
      };
}

class SaleItem {
  const SaleItem({
    this.id,
    this.saleId,
    this.productId,
    required this.productName,
    required this.qty,
    required this.unitPriceCentavos,
    this.unitCostCentavos = 0,
  });

  final int? id;
  final int? saleId;
  final int? productId;
  final String productName;
  final int qty;
  final int unitPriceCentavos;
  final int unitCostCentavos;

  int get lineTotalCentavos => unitPriceCentavos * qty;
  int get lineCostCentavos => unitCostCentavos * qty;
  int get lineProfitCentavos => lineTotalCentavos - lineCostCentavos;

  factory SaleItem.fromRow(Map<String, Object?> row) => SaleItem(
        id: row['id'] as int?,
        saleId: row['sale_id'] as int?,
        productId: row['product_id'] as int?,
        productName: row['product_name'] as String? ?? '',
        qty: (row['qty'] as int?) ?? 0,
        unitPriceCentavos: (row['unit_price_centavos'] as int?) ?? 0,
        unitCostCentavos: (row['unit_cost_centavos'] as int?) ?? 0,
      );
}

class Sale {
  const Sale({
    this.id,
    required this.soldAt,
    required this.totalCentavos,
    this.costCentavos = 0,
    this.paymentType = PaymentType.cash,
    this.customerId,
    this.customerName,
    this.note,
    this.voided = false,
    this.items = const [],
    this.itemCount = 0,
  });

  final int? id;
  final DateTime soldAt;
  final int totalCentavos;
  final int costCentavos;
  final PaymentType paymentType;
  final int? customerId;
  final String? customerName;
  final String? note;
  final bool voided;
  final List<SaleItem> items;

  /// Total pieces across all lines. Populated by list queries so the data
  /// table can show it without loading every line.
  final int itemCount;

  int get profitCentavos => totalCentavos - costCentavos;

  String get dayKey => Dates.dayKey(soldAt);

  factory Sale.fromRow(Map<String, Object?> row, {List<SaleItem>? items}) =>
      Sale(
        id: row['id'] as int?,
        soldAt:
            DateTime.fromMillisecondsSinceEpoch((row['sold_at'] as int?) ?? 0),
        totalCentavos: (row['total_centavos'] as int?) ?? 0,
        costCentavos: (row['cost_centavos'] as int?) ?? 0,
        paymentType: PaymentTypeX.fromCode(row['payment_type'] as String?),
        customerId: row['customer_id'] as int?,
        customerName: row['customer_name'] as String?,
        note: row['note'] as String?,
        voided: ((row['voided'] as int?) ?? 0) == 1,
        items: items ?? const [],
        itemCount: (row['item_count'] as int?) ?? 0,
      );
}

class LedgerEntry {
  const LedgerEntry({
    this.id,
    required this.customerId,
    this.saleId,
    required this.amountCentavos,
    required this.enteredAt,
    this.note,
  });

  final int? id;
  final int customerId;
  final int? saleId;

  /// Positive adds to what the customer owes, negative records a payment.
  final int amountCentavos;
  final DateTime enteredAt;
  final String? note;

  bool get isPayment => amountCentavos < 0;

  factory LedgerEntry.fromRow(Map<String, Object?> row) => LedgerEntry(
        id: row['id'] as int?,
        customerId: (row['customer_id'] as int?) ?? 0,
        saleId: row['sale_id'] as int?,
        amountCentavos: (row['amount_centavos'] as int?) ?? 0,
        enteredAt: DateTime.fromMillisecondsSinceEpoch(
          (row['entered_at'] as int?) ?? 0,
        ),
        note: row['note'] as String?,
      );
}

class StockMovement {
  const StockMovement({
    this.id,
    required this.productId,
    this.productName,
    required this.delta,
    required this.reason,
    this.costCentavos = 0,
    required this.movedAt,
    this.note,
  });

  final int? id;
  final int productId;
  final String? productName;
  final int delta;
  final StockReason reason;
  final int costCentavos;
  final DateTime movedAt;
  final String? note;

  factory StockMovement.fromRow(Map<String, Object?> row) => StockMovement(
        id: row['id'] as int?,
        productId: (row['product_id'] as int?) ?? 0,
        productName: row['product_name'] as String?,
        delta: (row['delta'] as int?) ?? 0,
        reason: StockReasonX.fromCode(row['reason'] as String?),
        costCentavos: (row['cost_centavos'] as int?) ?? 0,
        movedAt:
            DateTime.fromMillisecondsSinceEpoch((row['moved_at'] as int?) ?? 0),
        note: row['note'] as String?,
      );
}

class Expense {
  const Expense({
    this.id,
    required this.amountCentavos,
    required this.category,
    required this.spentAt,
    this.note,
  });

  final int? id;
  final int amountCentavos;
  final String category;
  final DateTime spentAt;
  final String? note;

  factory Expense.fromRow(Map<String, Object?> row) => Expense(
        id: row['id'] as int?,
        amountCentavos: (row['amount_centavos'] as int?) ?? 0,
        category: row['category'] as String? ?? 'Iba pa',
        spentAt:
            DateTime.fromMillisecondsSinceEpoch((row['spent_at'] as int?) ?? 0),
        note: row['note'] as String?,
      );
}

const List<String> expenseCategories = [
  'Paninda',
  'Kuryente',
  'Tubig',
  'Renta',
  'Pamasahe',
  'Iba pa',
];

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
