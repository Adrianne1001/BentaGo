import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// Renaming and removing categories.
///
/// There is no categories table -- a category is just text on a product row.
/// So renaming means updating every product carrying it, and "removing" means
/// clearing the field, never touching the products themselves. New categories
/// are created in the product form, where they are actually needed.
///
/// The flows live as top-level functions because two screens reach them: this
/// list, and a long-press on a category chip in Products.

/// Prompts for a new name and applies it to every product in [current].
Future<void> renameCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  String current, {
  List<String> existing = const [],
}) async {
  final controller = TextEditingController(text: current);
  final formKey = GlobalKey<FormState>();

  final renamed = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename category'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return 'Enter a name.';
            if (text.length > 30) return 'Keep it under 30 characters.';
            final clash = existing.any(
              (c) =>
                  c.toLowerCase() == text.toLowerCase() &&
                  c.toLowerCase() != current.toLowerCase(),
            );
            if (clash) return 'That category already exists.';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(context, controller.text.trim());
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );

  if (renamed == null || renamed == current) return;

  final changed = await ref
      .read(productRepositoryProvider)
      .renameCategory(current, renamed);
  ref.refreshData();

  // If the renamed category was the active filter, follow it -- otherwise the
  // list would silently empty out.
  if (ref.read(productCategoryFilterProvider) == current) {
    ref.read(productCategoryFilterProvider.notifier).state = renamed;
  }

  if (context.mounted) {
    showToast(
      context,
      changed == 1
          ? 'Renamed to "$renamed" on 1 product'
          : 'Renamed to "$renamed" on $changed products',
    );
  }
}

/// Clears [category] from every product. The products themselves stay.
Future<void> removeCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  String category, {
  int? count,
}) async {
  final affected =
      count ?? (await ref.read(productRepositoryProvider).categoryCounts())[category] ?? 0;

  if (!context.mounted) return;
  final ok = await confirmDestructive(
    context,
    title: 'Delete "$category"?',
    message: affected == 1
        ? 'The 1 product using it stays, just without a category.'
        : 'The $affected products using it stay, just without a category.',
    confirmLabel: 'Delete',
  );
  if (!ok) return;

  await ref.read(productRepositoryProvider).deleteCategory(category);

  // Clear the filter if it pointed at the category that just went away.
  if (ref.read(productCategoryFilterProvider) == category) {
    ref.read(productCategoryFilterProvider.notifier).state = null;
  }
  ref.refreshData();

  if (context.mounted) showToast(context, '"$category" deleted');
}

/// The rename / delete sheet shown when a category chip is held down.
Future<void> showCategoryActions(
  BuildContext context,
  WidgetRef ref,
  String category, {
  List<String> existing = const [],
  int? count,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.label_outline,
                  color: sheetContext.colors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename category'),
            subtitle: const Text('Updates every product using it'),
            onTap: () {
              Navigator.pop(sheetContext);
              renameCategoryFlow(context, ref, category, existing: existing);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: sheetContext.colors.danger,
            ),
            title: Text(
              'Delete category',
              style: TextStyle(color: sheetContext.colors.danger),
            ),
            subtitle: const Text('The products stay, without a category'),
            onTap: () {
              Navigator.pop(sheetContext);
              removeCategoryFlow(context, ref, category, count: count);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class CategoryManagerScreen extends ConsumerWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(categoryCountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: AsyncBlock<Map<String, int>>(
        value: counts,
        loadingHeight: 260,
        builder: (data) {
          if (data.isEmpty) {
            return const EmptyState(
              icon: Icons.label_outline,
              title: 'No categories yet',
              message: 'Add one while adding or editing a product — '
                  'tap "New" beside Category.',
            );
          }

          final names = data.keys.toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Text(
                  'Categories group the product grid on the Sell screen. '
                  'Create new ones from the product form.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: context.colors.muted,
                  ),
                ),
              ),
              for (final name in names)
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.label_outline,
                      size: 19,
                      color: context.colors.accent,
                    ),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    data[name] == 1 ? '1 product' : '${data[name]} products',
                    style:
                        TextStyle(fontSize: 12.5, color: context.colors.muted),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: 'Rename',
                        onPressed: () => renameCategoryFlow(
                          context,
                          ref,
                          name,
                          existing: names,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: context.colors.danger,
                        ),
                        tooltip: 'Delete',
                        onPressed: () => removeCategoryFlow(
                          context,
                          ref,
                          name,
                          count: data[name],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
