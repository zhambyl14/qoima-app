import 'package:flutter/material.dart';
import '../data/models/category_data.dart';
import 'qoima_design.dart';

// ── QCategoryTag — маленький тег категории товара ─────────────────────────────
class QCategoryTag extends StatelessWidget {
  final CategoryData category;
  final double fontSize;
  const QCategoryTag({super.key, required this.category, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final tone = toneFor(category.tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CategoryIcon(kind: category.iconKey, size: fontSize + 2, color: tone.deep),
          const SizedBox(width: 5),
          Text(category.short,
              style: manrope(fontSize, FontWeight.w700, color: tone.deep)),
        ],
      ),
    );
  }
}

// ── QStepIndicator — прогресс визарда ─────────────────────────────────────────
class QStepIndicator extends StatelessWidget {
  final List<String> steps;
  final int current; // 0-based
  final ValueChanged<int>? onStepTap; // разрешить переход только назад
  const QStepIndicator(
      {super.key, required this.steps, required this.current, this.onStepTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (onStepTap != null && i < current)
                  ? () => onStepTap!(i)
                  : null,
              child: Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= current ? cGreen : cBg,
                      border: Border.all(
                          color: i <= current ? cGreen : cLine, width: 2),
                    ),
                    child: Center(
                      child: i < current
                          ? const Icon(Icons.check, size: 15, color: Colors.white)
                          : Text('${i + 1}',
                              style: manrope(12, FontWeight.w800,
                                  color: i <= current ? Colors.white : cInk3)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(steps[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manrope(10, FontWeight.w700,
                          color: i == current ? cGreen : cInk3)),
                ],
              ),
            ),
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                width: 18,
                height: 2,
                color: i < current ? cGreen : cLine,
              ),
            ),
        ],
      ],
    );
  }
}

// ── QSizeGrid — сетка размеров (одиночный выбор) ──────────────────────────────
class QSizeGrid extends StatelessWidget {
  final List<String> sizes;
  final int selected; // индекс выбранного, -1 если нет
  final List<int> disabled; // индексы недоступных
  final ValueChanged<int>? onTap;

  const QSizeGrid({
    super.key,
    required this.sizes,
    this.selected = -1,
    this.disabled = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: List.generate(sizes.length, (i) {
        final isOn = i == selected;
        final isOff = disabled.contains(i);
        return GestureDetector(
          onTap: isOff ? null : () => onTap?.call(i),
          child: Container(
            width: 56,
            height: 50,
            decoration: BoxDecoration(
              color: isOn ? cGreenTint : (isOff ? cLine2 : cSurface),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: isOn ? cGreen : cLine, width: isOn ? 1.8 : 1.5),
            ),
            child: Center(
              child: Text(sizes[i],
                  style: manrope(15, FontWeight.w800,
                      color: isOff ? cInk3 : (isOn ? cGreenDeep : cInk))),
            ),
          ),
        );
      }),
    );
  }
}

// ── QSizeQtyGrid — размеры с количеством (для визарда) ────────────────────────
class QSizeQtyGrid extends StatelessWidget {
  final List<String> sizes;
  final List<int> quantities; // длина = sizes.length
  final ValueChanged<List<int>>? onChanged;

  const QSizeQtyGrid({
    super.key,
    required this.sizes,
    required this.quantities,
    this.onChanged,
  });

  void _set(int i, int value) {
    final next = List<int>.from(quantities);
    next[i] = value.clamp(0, 9999);
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(sizes.length, (i) {
        final qty = i < quantities.length ? quantities[i] : 0;
        final on = qty > 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: on ? cGreenTint : cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: on ? cGreen.withValues(alpha: 0.33) : cLine, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 40,
                decoration: BoxDecoration(
                  color: on ? cGreen : cLine2,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(sizes[i],
                      style: manrope(14.5, FontWeight.w800,
                          color: on ? Colors.white : cInk2)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(on ? '$qty шт' : 'Нет',
                    style: manrope(13.5, FontWeight.w600, color: cInk2)),
              ),
              _QtyBtn(
                  icon: Icons.remove_rounded,
                  bg: cBg,
                  fg: cInk2,
                  onTap: () => _set(i, qty - 1)),
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                child: Text('$qty',
                    textAlign: TextAlign.center,
                    style: manrope(16, FontWeight.w800, color: cInk)),
              ),
              const SizedBox(width: 10),
              _QtyBtn(
                  icon: Icons.add_rounded,
                  bg: cGreen,
                  fg: Colors.white,
                  onTap: () => _set(i, qty + 1)),
            ],
          ),
        );
      }),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final VoidCallback onTap;
  const _QtyBtn(
      {required this.icon,
      required this.bg,
      required this.fg,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: fg),
        ),
      );
}

// ── QLazyLoadIndicator — индикатор подгрузки при скролле ──────────────────────
class QLazyLoadIndicator extends StatelessWidget {
  final int loaded;
  final int total;
  final bool isLoading;
  final VoidCallback? onLoadMore;

  const QLazyLoadIndicator({
    super.key,
    required this.loaded,
    required this.total,
    required this.isLoading,
    this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (total > 0 && loaded >= total && !isLoading) {
      return const SizedBox.shrink();
    }
    final factor = total > 0 ? (loaded / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          if (total > 0)
            Text('Показано $loaded из $total',
                style: manrope(12, FontWeight.w600, color: cInk3)),
          const SizedBox(height: 8),
          if (total > 0)
            Container(
              width: 160,
              height: 4,
              decoration: BoxDecoration(
                  color: cLine2, borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: factor,
                child: Container(
                    decoration: BoxDecoration(
                        color: cGreen, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          const SizedBox(height: 8),
          if (isLoading)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: cGreen))
          else if (onLoadMore != null)
            GestureDetector(
              onTap: onLoadMore,
              behavior: HitTestBehavior.opaque,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 16, color: cGreen),
                const SizedBox(width: 4),
                Text('Загрузить ещё',
                    style: manrope(12.5, FontWeight.w700, color: cGreen)),
              ]),
            ),
        ],
      ),
    );
  }
}
