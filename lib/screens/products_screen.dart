import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';
import 'category_manager.dart';
import 'product_form_screen.dart';

enum _ProductView { list, table }

/// The product register: names, prices and costs. Two ways to look at the same
/// rows -- a touch-friendly list for everyday edits, and a scrollable table for
/// comparing prices and margins across the whole shelf at once.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  _ProductView _view = _ProductView.list;

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

  void _openCategories() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CategoryManagerScreen()),
    );
  }

  Future<void> _editCategory(String category) async {
    final existing =
        ref.read(productCategoriesProvider).valueOrNull ?? const <String>[];
    await showCategoryActions(context, ref, category, existing: existing);
  }

  Future<void> _confirmDelete(Product product) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete ${product.name}?',
      message: 'Past sales of this product stay in the records and in the '
          'reports. It just stops appearing in the product list.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;

    await ref.read(productRepositoryProvider).delete(product.id!);
    ref.refreshData();
    if (mounted) showToast(context, '${product.name} deleted');
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
                          '${Money.format(product.priceCentavos)} per '
                          '${product.unitLabel}'
                          '${product.hasCost ? ' · ${Money.format(product.marginCentavos)} profit' : ''}',
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
              title: const Text('Edit details'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openForm(product: product);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: sheetContext.colors.danger,
              ),
              title: Text(
                'Delete',
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
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: Icon(
              _view == _ProductView.list
                  ? Icons.table_chart_outlined
                  : Icons.view_list_outlined,
            ),
            tooltip: _view == _ProductView.list ? 'Table view' : 'List view',
            onPressed: () => setState(
              () => _view = _view == _ProductView.list
                  ? _ProductView.table
                  : _ProductView.list,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Categories',
            onPressed: _openCategories,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppSearchField(
              hint: 'Search products...',
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
            onManage: _openCategories,
            onEditOne: _editCategory,
          ),
          Expanded(
            child: AsyncBlock<List<Product>>(
              value: products,
              loadingHeight: 300,
              builder: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.sell_outlined,
                    title: search.isEmpty ? 'No products yet' : 'No matches',
                    message: search.isEmpty
                        ? 'A name and a price is all it takes.'
                        : 'Nothing matches "$search".',
                    action: FilledButton.icon(
                      onPressed: () => _openForm(
                        initialName: search.isEmpty ? null : search,
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add a product'),
                    ),
                  );
                }

                return _view == _ProductView.list
                    ? _ProductList(products: items, onTap: _showActions)
                    : _ProductTable(products: items, onTap: _showActions);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New product'),
      ),
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    required this.onEditOne,
  });

  final AsyncValue<List<String>> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onManage;
  final ValueChanged<String> onEditOne;

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
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          // Tapping filters; holding renames or removes. The visible Edit chip
          // at the end is what makes the second action findable at all -- a
          // long-press nobody knows about is not a feature.
          for (final category in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: GestureDetector(
                onLongPress: () => onEditOne(category),
                child: ChoiceChip(
                  label: Text(category),
                  selected: selected == category,
                  onSelected: (_) =>
                      onSelect(selected == category ? null : category),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ActionChip(
              avatar: Icon(
                Icons.edit_outlined,
                size: 16,
                color: context.colors.accent,
              ),
              label: const Text('Edit'),
              onPressed: onManage,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: ProductAvatar(product: product, size: 44),
          title: Text(
            product.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              product.category == null
                  ? 'per ${product.unitLabel}'
                  : '${product.category} · per ${product.unitLabel}',
              style: TextStyle(fontSize: 12.5, color: context.colors.muted),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(product.priceCentavos),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                margin == null
                    ? 'no cost set'
                    : '${Money.formatShort(product.marginCentavos)} · ${margin.round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  color: margin == null
                      ? context.colors.muted
                      : context.colors.good,
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
            DataColumn(label: Text('PRODUCT')),
            DataColumn(label: Text('CATEGORY')),
            DataColumn(label: Text('UNIT')),
            DataColumn(label: Text('PRICE'), numeric: true),
            DataColumn(label: Text('COST'), numeric: true),
            DataColumn(label: Text('PROFIT'), numeric: true),
            DataColumn(label: Text('MARGIN'), numeric: true),
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
                  DataCell(
                    Text(
                      product.unitLabel,
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                  DataCell(Text(Money.plain(product.priceCentavos))),
                  DataCell(
                    Text(
                      product.hasCost
                          ? Money.plain(product.costCentavos)
                          : '--',
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
                        color: product.hasCost
                            ? context.colors.good
                            : context.colors.muted,
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
                ],
              ),
          ],
        ),
      ),
    );
  }
}
