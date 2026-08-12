enum PaymentType { cash, credit, gcash }

extension PaymentTypeX on PaymentType {
  String get code => name;

  String get label => switch (this) {
        PaymentType.cash => 'Cash',
        PaymentType.credit => 'Credit',
        PaymentType.gcash => 'GCash',
      };

  /// The local word for a tab. Shown alongside the English label where the
  /// distinction matters, because this is what the store actually calls it.
  String get localLabel => switch (this) {
        PaymentType.cash => 'Cash',
        PaymentType.credit => 'Utang',
        PaymentType.gcash => 'GCash',
      };

  static PaymentType fromCode(String? code) => switch (code) {
        // 'utang' was the stored code before the interface moved to English.
        'credit' || 'utang' => PaymentType.credit,
        'gcash' => PaymentType.gcash,
        _ => PaymentType.cash,
      };
}

/// A single sellable item: a name, a price, and optionally a cost.
///
/// Only [name] and [priceCentavos] are required; every other field may be
/// blank, and the interface degrades gracefully when they are. There is no
/// stock count -- the app never claims to know what is on the shelf.
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
  final bool archived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Peso margin on one piece. Zero when no cost has been entered, which is
  /// fine -- profit reporting treats those items as pure revenue and the
  /// reports screen labels the figure as an estimate.
  int get marginCentavos => priceCentavos - costCentavos;

  bool get hasCost => costCentavos > 0;

  /// Profit as a share of the **selling price**. This is what the Reports screen
  /// and the products table mean by "margin", and it is the figure that composes
  /// with revenue: a 20% margin on ₱1,000 of sales is ₱200 of profit.
  double? get marginPercent {
    if (priceCentavos <= 0 || !hasCost) return null;
    return marginCentavos / priceCentavos * 100;
  }

  /// Profit as a share of the **cost** -- what gets added on top of what the
  /// store paid. This is the figure the product form asks for, because it is how
  /// buying decisions are actually made ("I paid ₱14, I sell at ₱17").
  ///
  /// Deliberately a different number from [marginPercent] on the same product:
  /// ₱14 cost at ₱17 is a 21.4% markup and an 17.6% margin. The form prints both
  /// so the two can never be silently confused.
  double? get markupPercent => markupFor(costCentavos, priceCentavos);

  /// Selling price implied by a cost and a markup, rounded to the centavo.
  static int priceFromMarkup(int costCentavos, double markupPercent) =>
      (costCentavos * (1 + markupPercent / 100)).round();

  /// The markup a chosen price implies. Null when there is no cost to mark up
  /// from -- an undefined percentage, not a zero one.
  static double? markupFor(int costCentavos, int priceCentavos) {
    if (costCentavos <= 0) return null;
    return (priceCentavos - costCentavos) / costCentavos * 100;
  }

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
        'created_at': createdAt?.millisecondsSinceEpoch ??
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
        category: row['category'] as String? ?? 'Other',
        spentAt:
            DateTime.fromMillisecondsSinceEpoch((row['spent_at'] as int?) ?? 0),
        note: row['note'] as String?,
      );
}

const List<String> expenseCategories = [
  'Stock',
  'Electricity',
  'Water',
  'Rent',
  'Transport',
  'Other',
];

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
