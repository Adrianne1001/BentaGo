import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'product_form_screen.dart';

enum _StockView { list, table }

/// Paninda: the product register. Two ways to look at the same rows -- a
/// touch-friendly list for everyday edits, and a scrollable table for when she
/// wants to compare prices and margins across the whole shelf at once.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  _StockView _view = _StockView.list;

  Future<void> _openForm({Product? product, String? initialName}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(
          product: product,
          initialName: initialName,
        ),
      ),
    );
  }

  Future<void> _receiveDelivery(Product product) async {
    final result = await showDialog<_DeliveryResult>(
      context: context,
      builder: (context) => _DeliveryDialog(product: product),
    );
    if (result == null) return;

    await ref.read(productRepositoryProvider).receiveDelivery(
          productId: product.id!,
          qty: result.qty,
          newUnitCostCentavos: result.unitCostCentavos,
        );
    ref.refreshData();
    if (mounted) {
      showToast(
        context,
        'Naidagdag: ${result.qty} ${product.unitLabel} ng ${product.name}',
      );
    }
  }

  Future<void> _reduceStock(Product product) async {
    final result = await showDialog<_ReduceResult>(
      context: context,
      builder: (context) => _ReduceDialog(product: product),
    );
    if (result == null) return;

    await ref.read(productRepositoryProvider).adjustStock(
          productId: product.id!,
          delta: -result.qty,
          reason: result.reason,
          note: result.reason.label,
        );
    ref.refreshData();
    if (mounted) {
      showToast(context, 'Nabawasan ang stock ng ${product.name}');
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final ok = await confirmDestructive(
      context,
      title: 'Burahin ang ${product.name}?',
      message: 'Mananatili ang mga lumang benta nito sa talaan at sa ulat. '
          'Hindi na lang ito lalabas sa listahan ng paninda.',
      confirmLabel: 'Burahin',
    );
    if (!ok) return;

    await ref.read(productRepositoryProvider).delete(product.id!);
    ref.refreshData();
    if (mounted) showToast(context, 'Nabura ang ${product.name}');
  }

  void _showActions(Product product) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  ProductAvatar(product: product, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${Money.format(product.priceCentavos)} kada '
                          '${product.unitLabel}'
                          '${product.trackStock ? ' · ${product.stock} natitira' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: sheetContext.colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('I-edit ang detalye'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openForm(product: product);
              },
            ),
            if (product.trackStock) ...[
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('May dumating na delivery'),
                subtitle: const Text('Dagdagan ang stock'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _receiveDelivery(product);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: const Text('Bawasan ang stock'),
                subtitle: const Text('Sira, expired, o kinuha sa bahay'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _reduceStock(product);
                },
              ),
            ],
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: sheetContext.colors.danger,
              ),
              title: Text(
                'Burahin',
                style: TextStyle(color: sheetContext.colors.danger),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(product);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productListProvider);
    final search = ref.watch(productSearchProvider);
    final categories = ref.watch(productCategoriesProvider);
    final selectedCategory = ref.watch(productCategoryFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paninda'),
        actions: [
          IconButton(
            icon: Icon(
              _view == _StockView.list
                  ? Icons.table_chart_outlined
                  : Icons.view_list_outlined,
            ),
            tooltip: _view == _StockView.list
                ? 'Talahanayan'
                : 'Listahan',
            onPressed: () => setState(
              () => _view = _view == _StockView.list
                  ? _StockView.table
                  : _StockView.list,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(
              hint: 'Hanapin ang paninda...',
              value: search,
              onChanged: (value) =>
                  ref.read(productSearchProvider.notifier).state = value,
            ),
          ),
          _CategoryFilterRow(
            categories: categories,
            selected: selectedCategory,
            onSelect: (value) =>
                ref.read(productCategoryFilterProvider.notifier).state = value,
          ),
          Expanded(
            child: AsyncBlock<List<Product>>(
              value: products,
              loadingHeight: 300,
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: search.isEmpty
                        ? 'Wala pang paninda'
                        : 'Walang nahanap',
                    message: search.isEmpty
                        ? 'Ang kailangan lang ay pangalan at presyo.'
                        : 'Walang tugma sa "$search".',
                    action: FilledButton.icon(
                      onPressed: () => _openForm(
                        initialName: search.isEmpty ? null : search,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Magdagdag ng produkto'),
                    ),
                  );
                }

                return _view == _StockView.list
                    ? _ProductList(
                        products: items,
                        onTap: _showActions,
                      )
                    : _ProductTable(products: items, onTap: _showActions);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Bagong paninda'),
      ),
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final AsyncValue<List<String>> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = categories.valueOrNull ?? const <String>[];
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ChoiceChip(
              label: const Text('Lahat'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          for (final category in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: ChoiceChip(
                label: Text(category),
                selected: selected == category,
                onSelected: (_) =>
                    onSelect(selected == category ? null : category),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: products.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        final margin = product.marginPercent;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ProductAvatar(product: product, size: 44),
          title: Text(
            product.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  '${Money.format(product.priceCentavos)} / ${product.unitLabel}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.scheme.primary,
                  ),
                ),
                if (margin != null)
                  Text(
                    '· ${margin.round()}% margin',
                    style: TextStyle(fontSize: 12.5, color: context.colors.muted),
                  )
                else
                  Text(
                    '· walang puhunan',
                    style: TextStyle(fontSize: 12.5, color: context.colors.muted),
                  ),
              ],
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!product.trackStock)
                PillTag(text: 'Walang bilang', color: context.colors.muted)
              else if (product.isOutOfStock)
                PillTag(text: 'Ubos na', color: context.colors.danger)
              else
                Text(
                  '${product.stock}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: product.isLowStock
                        ? context.colors.warn
                        : context.scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (product.trackStock && !product.isOutOfStock)
                Text(
                  product.isLowStock ? 'mababa na' : 'natitira',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: product.isLowStock
                        ? context.colors.warn
                        : context.colors.muted,
                  ),
                ),
            ],
          ),
          onTap: () => onTap(product),
        );
      },
    );
  }
}

/// The whole shelf as a scrollable grid of figures. Wrapped in a horizontal
/// scroll view so the page body never scrolls sideways with it.
class _ProductTable extends StatelessWidget {
  const _ProductTable({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 96),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: context.colors.muted,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 13.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          columnSpacing: 22,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('PANINDA')),
            DataColumn(label: Text('KATEGORYA')),
            DataColumn(label: Text('PRESYO'), numeric: true),
            DataColumn(label: Text('PUHUNAN'), numeric: true),
            DataColumn(label: Text('KITA/PC'), numeric: true),
            DataColumn(label: Text('MARGIN'), numeric: true),
            DataColumn(label: Text('STOCK'), numeric: true),
          ],
          rows: [
            for (final product in products)
              DataRow(
                onSelectChanged: (_) => onTap(product),
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      product.category ?? '--',
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(Text(Money.plain(product.priceCentavos))),
                  DataCell(
                    Text(
                      product.hasCost ? Money.plain(product.costCentavos) : '--',
                      style: product.hasCost
                          ? null
                          : TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(
                    Text(
                      product.hasCost
                          ? Money.plain(product.marginCentavos)
                          : '--',
                      style: TextStyle(
                        color: product.hasCost ? context.colors.good : context.colors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      product.marginPercent == null
                          ? '--'
                          : '${product.marginPercent!.round()}%',
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(
                    Text(
                      product.trackStock ? '${product.stock}' : '--',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: product.trackStock && product.isLowStock
                            ? context.colors.warn
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// --- dialogs --------------------------------------------------------------

class _DeliveryResult {
  const _DeliveryResult({required this.qty, this.unitCostCentavos});

  final int qty;
  final int? unitCostCentavos;
}

class _DeliveryDialog extends StatefulWidget {
  const _DeliveryDialog({required this.product});

  final Product product;

  @override
  State<_DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<_DeliveryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  late final TextEditingController _costController;

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: widget.product.hasCost
          ? Money.plain(widget.product.costCentavos)
          : '',
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dumating na delivery'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Ngayon: ${widget.product.stock} ${widget.product.unitLabel}',
              style: TextStyle(fontSize: 13, color: context.colors.muted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _qtyController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Ilang ${widget.product.unitLabel} ang dumating?',
              ),
              validator: (raw) {
                final value = int.tryParse((raw ?? '').trim());
                if (value == null || value <= 0) return 'Maglagay ng bilang.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _costController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Puhunan kada piraso',
                prefixText: '₱ ',
                helperText: 'Opsyonal. Iwanang blangko kung walang pagbabago.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kanselahin'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _DeliveryResult(
                qty: int.parse(_qtyController.text.trim()),
                unitCostCentavos: Money.parse(_costController.text),
              ),
            );
          },
          child: const Text('Idagdag'),
        ),
      ],
    );
  }
}

class _ReduceResult {
  const _ReduceResult({required this.qty, required this.reason});

  final int qty;
  final StockReason reason;
}

class _ReduceDialog extends StatefulWidget {
  const _ReduceDialog({required this.product});

  final Product product;

  @override
  State<_ReduceDialog> createState() => _ReduceDialogState();
}

class _ReduceDialogState extends State<_ReduceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  StockReason _reason = StockReason.spoilage;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bawasan ang stock'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Ngayon: ${widget.product.stock} ${widget.product.unitLabel}',
              style: TextStyle(fontSize: 13, color: context.colors.muted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _qtyController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ilan ang bawas?'),
              validator: (raw) {
                final value = int.tryParse((raw ?? '').trim());
                if (value == null || value <= 0) return 'Maglagay ng bilang.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            Text(
              'Bakit?',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.colors.muted,
              ),
            ),
            const SizedBox(height: 6),
            // Household use is a real, frequent category. Without it the stock
            // count never reconciles and she stops trusting the number.
            for (final reason in const [
              StockReason.spoilage,
              StockReason.personal,
              StockReason.correction,
            ])
              RadioListTile<StockReason>(
                value: reason,
                groupValue: _reason,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(reason.label),
                onChanged: (value) => setState(() => _reason = value!),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kanselahin'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(
              context,
              _ReduceResult(
                qty: int.parse(_qtyController.text.trim()),
                reason: _reason,
              ),
            );
          },
          child: const Text('I-save'),
        ),
      ],
    );
  }
}
