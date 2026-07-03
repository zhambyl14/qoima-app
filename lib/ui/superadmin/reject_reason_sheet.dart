import 'package:flutter/material.dart';
import '../../theme/qoima_design.dart';

/// Бас тарту/қайтару себебін таңдау bottom-sheet (v10 §6). Radio-пресет таңдалғанда
/// комментарий өрісіне автоматты қойылады, бірақ оны өңдеуге болады. Растағанда
/// финал мәтінді қайтарады (бос болса — null). Заявка + өзгерту запросы reject-те қолданылады.
Future<String?> showRejectReasonSheet(
  BuildContext context, {
  String title = 'Причина отклонения',
  String subtitle = '',
  List<String>? reasons,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RejectReasonSheet(
      title: title,
      subtitle: subtitle,
      reasons: reasons ?? _defaultReasons,
    ),
  );
}

const _defaultReasons = [
  'Владелец карты не совпадает с ИИН',
  'ИИН/БИН указан неверно',
  'Недостаточное описание магазина',
  'Повторная заявка (магазин существует)',
  'Поддельные документы',
];

class _RejectReasonSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> reasons;
  const _RejectReasonSheet({
    required this.title,
    required this.subtitle,
    required this.reasons,
  });

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  int _selected = -1;
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  void _pick(int i) {
    setState(() {
      _selected = i;
      _noteCtrl.text = widget.reasons[i];
    });
  }

  void _confirm() {
    final t = _noteCtrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
    final canConfirm = _noteCtrl.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottom),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              QIconTile(
                icon: const Icon(Icons.cancel_outlined, color: cRed, size: 20),
                tone: 'red',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: manrope(16.5, FontWeight.w800, color: cInk)),
                    if (widget.subtitle.isNotEmpty)
                      Text(widget.subtitle,
                          style:
                              manrope(12.5, FontWeight.w500, color: cInk3)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            const QSecLabel('Выберите причину'),
            ...List.generate(widget.reasons.length, (i) {
              final sel = _selected == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _pick(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? cRedTint : cSurface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: sel ? cRed : cLine, width: 1.5),
                    ),
                    child: Row(children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: sel ? cRed : cInk3, width: 2),
                        ),
                        child: sel
                            ? Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      color: cRed, shape: BoxShape.circle),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(widget.reasons[i],
                            style: manrope(13.5,
                                sel ? FontWeight.w700 : FontWeight.w600,
                                color: sel ? const Color(0xFFB11A2B) : cInk2)),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            const QSecLabel('Комментарий (виден владельцу)'),
            Container(
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine, width: 1.5),
              ),
              child: TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() {}),
                style: manrope(14.5, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: 'Опишите причину...',
                  hintStyle: manrope(14.5, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: canConfirm ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cRed,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: cRed.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.close_rounded,
                        color: Colors.white, size: 19),
                    const SizedBox(width: 8),
                    Text('Подтвердить отклонение',
                        style: manrope(15, FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cInk2,
                  side: const BorderSide(color: cLine),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text('Отмена',
                    style: manrope(14.5, FontWeight.w700, color: cInk2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
