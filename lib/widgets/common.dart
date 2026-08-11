import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/models.dart';

/// A titled block. Every screen is a column of these, which keeps spacing and
/// heading weight consistent without each screen inventing its own.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.colors.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

enum StatTone { neutral, good, warn, danger, accent }

/// A headline number with its label. The value uses tabular figures so a row
/// of tiles lines up on the decimal point.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone = StatTone.neutral,
    this.icon,
    this.onTap,
    this.large = false,
  });

  final String label;
  final String value;
  final String? caption;
  final StatTone tone;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool large;

  Color _toneColor(BuildContext context) => switch (tone) {
        StatTone.neutral => context.scheme.onSurface,
        StatTone.good => context.colors.good,
        StatTone.warn => context.colors.warn,
        StatTone.danger => context.colors.danger,
        StatTone.accent => context.colors.accent,
      };

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context);

    return Material(
      color: context.scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.all(large ? 18 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: color.withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: large ? 30 : 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.colors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The product tile face: the chosen emoji, or the first letter on a tint
/// derived from the name so the same product keeps the same colour.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({
    super.key,
    required this.product,
    this.size = 44,
  });

  final Product product;
  final double size;

  static const List<Color> _tints = [
    Color(0xFF1B4D6B),
    Color(0xFF2C6E4E),
    Color(0xFFA9761A),
    Color(0xFF7A3B6B),
    Color(0xFF9A4A19),
    Color(0xFF3F6BA8),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[product.name.hashCode.abs() % _tints.length];
    final emoji = product.emoji;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: emoji != null && emoji.isNotEmpty
          ? Text(emoji, style: TextStyle(fontSize: size * 0.5))
          : Text(
              product.initial,
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
    );
  }
}

class PillTag extends StatelessWidget {
  const PillTag({
    super.key,
    required this.text,
    this.color,
    this.icon,
    this.filled = true,
  });

  final String text;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? tint.withValues(alpha: 0.14) : null,
        border: filled
            ? null
            : Border.all(color: tint.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tint,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

Color paymentColor(BuildContext context, PaymentType type) => switch (type) {
      PaymentType.cash => context.colors.cashTint,
      PaymentType.utang => context.colors.utangTint,
      PaymentType.gcash => context.colors.gcashTint,
    };

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: context.colors.muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.muted,
                  height: 1.45,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders an AsyncValue without every screen repeating the same three cases.
class AsyncBlock<T> extends StatelessWidget {
  const AsyncBlock({
    super.key,
    required this.value,
    required this.builder,
    this.loadingHeight = 120,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final double loadingHeight;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => SizedBox(
        height: loadingHeight,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.colors.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'May problema sa pagbasa ng datos.\n$error',
                style: TextStyle(fontSize: 13, color: context.colors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
  });

  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 22),
        suffixIcon: value.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Burahin',
                onPressed: () => onChanged(''),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

/// The keypad-friendly quantity control used in the basket and the stock
/// screen. Buttons are deliberately oversized for one-handed use.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.qty,
    required this.onChanged,
    this.min = 0,
    this.compact = false,
  });

  final int qty;
  final ValueChanged<int> onChanged;
  final int min;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 40.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          size: size,
          enabled: qty > min,
          onTap: () => onChanged(qty - 1),
        ),
        Container(
          constraints: BoxConstraints(minWidth: compact ? 34 : 44),
          alignment: Alignment.center,
          child: Text(
            '$qty',
            style: TextStyle(
              fontSize: compact ? 15 : 17,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          size: size,
          enabled: true,
          onTap: () => onChanged(qty + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? context.scheme.primary.withValues(alpha: 0.10)
          : context.scheme.outlineVariant.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.5,
            color: enabled ? context.scheme.primary : context.colors.muted,
          ),
        ),
      ),
    );
  }
}

/// A prompt for a peso amount. Returns centavos, or null when cancelled.
Future<int?> showAmountDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'I-save',
  int? initialCentavos,
}) async {
  final controller = TextEditingController(
    text: initialCentavos == null ? '' : Money.plain(initialCentavos),
  );
  final formKey = GlobalKey<FormState>();

  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message != null) ...[
              Text(
                message,
                style: TextStyle(fontSize: 13.5, color: context.colors.muted),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                prefixText: '₱ ',
                hintText: '0.00',
              ),
              validator: (raw) {
                final parsed = Money.parse(raw ?? '');
                if (parsed == null) return 'Maglagay ng halaga.';
                if (parsed <= 0) return 'Dapat mas mataas sa zero.';
                return null;
              },
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
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(context, Money.parse(controller.text));
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ituloy',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Huwag'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.danger,
            minimumSize: const Size(0, 46),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showToast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 5 : 3),
        backgroundColor: isError ? context.colors.danger : null,
      ),
    );
}
