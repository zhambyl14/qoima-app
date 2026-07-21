import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// HSV түс таңдағыш (S/V алаңы + hue жолағы + жылдам пресеттер). Таңдалған
/// [Color]-ды қайтарады (болдырмаса — null). Дүкен иесі стандарт палитрада жоқ
/// ерекше түсті таңдағанда қолданылады.
Future<Color?> showCustomColorPicker(BuildContext context,
    {Color initial = const Color(0xFF12C97A)}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ColorPickerSheet(initial: initial),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  String get _hex {
    String ch(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final c = _color;
    return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}'.toUpperCase();
  }

  static final List<Color> _quick = [
    const Color(0xFF00713F), const Color(0xFF12C97A),
    const Color(0xFF1A5BD0), const Color(0xFF5A3DD0),
    const Color(0xFFB11A2B), const Color(0xFFE8590C),
    const Color(0xFFC2255C), const Color(0xFF9A6A06),
    const Color(0xFF0C120F), const Color(0xFF3C4D45),
  ];

  void _setSv(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  void _setHue(Offset local, double width) {
    final h = (local.dx / width).clamp(0.0, 1.0) * 360;
    setState(() => _hsv = _hsv.withHue(h.clamp(0, 359.9)));
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Row(children: [
          Expanded(
            child: Text(tr('Выбор цвета', 'Түс таңдау'),
                style: manrope(17, FontWeight.w800, color: cInk)),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(
                color: cBg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: cLine),
                ),
              ),
              const SizedBox(width: 8),
              Text(_hex, style: manrope(12.5, FontWeight.w800, color: cInk)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (ctx, constraints) {
          final size = Size(constraints.maxWidth, 180.0);
          return GestureDetector(
            onPanDown: (d) => _setSv(d.localPosition, size),
            onPanUpdate: (d) => _setSv(d.localPosition, size),
            child: Container(
              width: size.width,
              height: size.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient:
                        LinearGradient(colors: [Colors.white, hueColor]),
                  ),
                  child: const SizedBox.expand(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
                Positioned(
                  left: (_hsv.saturation * size.width - 10)
                      .clamp(0.0, size.width - 20),
                  top: ((1 - _hsv.value) * size.height - 10)
                      .clamp(0.0, size.height - 20),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          return GestureDetector(
            onPanDown: (d) => _setHue(d.localPosition, w),
            onPanUpdate: (d) => _setHue(d.localPosition, w),
            child: SizedBox(
              height: 34,
              child: Stack(children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: LinearGradient(colors: [
                        for (var h = 0; h <= 360; h += 30)
                          HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor(),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: (_hsv.hue / 360 * w - 11).clamp(0.0, w - 22),
                  top: 0,
                  child: Container(
                    width: 22,
                    height: 34,
                    decoration: BoxDecoration(
                      color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _quick
                .map((c) => GestureDetector(
                      onTap: () =>
                          setState(() => _hsv = HSVColor.fromColor(c)),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cLine),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        QPrimaryButton(
          label: tr('Выбрать этот цвет', 'Осы түсті таңдау'),
          onPressed: () => Navigator.pop(context, _color),
          height: 50,
        ),
      ]),
    );
  }
}
