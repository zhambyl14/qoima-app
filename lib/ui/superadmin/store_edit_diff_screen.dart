import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../data/models/store_edit_request_model.dart';
import '../../data/repositories/store_edit_repository.dart';
import '../../theme/qoima_design.dart';
import '../shared/edit_field_display.dart';
import 'reject_reason_sheet.dart';

import '../../core/lang.dart';
const _editRejectReasons = [
  'Данные не соответствуют действительности',
  'Карта не совпадает с владельцем ИИН',
  'Недостаточно информации для проверки',
  'Подозрение на мошенничество',
  'Нарушение правил маркетплейса',
];

/// Superadmin — өзгерту запросының Было → Новое diff детальі (v10 §11).
class StoreEditDiffScreen extends StatefulWidget {
  final StoreEditRequestModel req;
  const StoreEditDiffScreen({super.key, required this.req});

  @override
  State<StoreEditDiffScreen> createState() => _StoreEditDiffScreenState();
}

class _StoreEditDiffScreenState extends State<StoreEditDiffScreen> {
  final _repo = StoreEditRepository();
  bool _loading = false;

  StoreEditRequestModel get req => widget.req;

  Future<void> _approve() async {
    setState(() => _loading = true);
    try {
      await _repo.approveEdit(
        req: req,
        reviewedBy: Supabase.instance.client.auth.currentUser!.id,
      );
      if (mounted) {
        Navigator.pop(context);
        _snack(tr('Изменения применены', 'Өзгерістер қолданылды'), cGreen);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.toString(), cRed);
      }
    }
  }

  Future<void> _reject() async {
    final note = await showRejectReasonSheet(
      context,
      title: tr('Вернуть изменения', 'Өзгерістерді қайтару'),
      subtitle: req.shopName,
      reasons: _editRejectReasons,
    );
    if (note == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await _repo.rejectEdit(
        editId: req.id,
        reviewedBy: Supabase.instance.client.auth.currentUser!.id,
        reviewNote: note,
      );
      if (mounted) {
        Navigator.pop(context);
        _snack(tr('Запрос возвращён владельцу', 'Сұраныс иесіне қайтарылды'), cInk);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.toString(), cRed);
      }
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final idShort =
        req.id.length >= 6 ? req.id.substring(0, 6).toUpperCase() : req.id;
    final cardChanged = req.changes.any((c) => c.field == 'paymentCardNumber');

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Изменение #$idShort', 'Өзгеріс #$idShort'),
          subtitle: '${req.shopName} · ${_fmtDate(req.createdAt)}',
          showBack: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QCard(
                  child: Row(children: [
                    QIconTile(
                      icon: const Icon(Icons.storefront_rounded,
                          color: cGreen, size: 20),
                      tone: 'green',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(req.shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  manrope(15, FontWeight.w800, color: cInk)),
                          Text(
                              'Отправлено: ${_fmtDateTime(req.createdAt)} · '
                              '${req.changes.length} изм.',
                              style: manrope(11.5, FontWeight.w500,
                                  color: cInk3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    QPill(_statusLabel(req), tone: _statusTone(req)),
                  ]),
                ),

                const SizedBox(height: 18),
                QSecLabel(tr('Изменения', 'Өзгерістер')),
                ...req.changes.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DiffCard(
                        label: c.label,
                        icon: editFieldIcon(c.field),
                        oldValue: editFieldDisplay(c.field, c.oldValue),
                        newValue: editFieldDisplay(c.field, c.newValue),
                      ),
                    )),

                if (cardChanged) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cAmberTint,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(children: [
                      const Icon(Icons.shield_outlined,
                          color: cAmber, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            'Изменён номер карты — проверьте, что владелец '
                            'совпадает с ИИН перед одобрением.',
                            style: manrope(12, FontWeight.w600,
                                color: const Color(0xFF7A4F00), height: 1.4)),
                      ),
                    ]),
                  ),
                ],

                if (req.ownerComment.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  QSecLabel(tr('Комментарий владельца', 'Иесінің пікірі')),
                  QCard(
                    child: Text(req.ownerComment,
                        style: manrope(13.5, FontWeight.w500,
                                color: cInk2, height: 1.45)
                            .copyWith(fontStyle: FontStyle.italic)),
                  ),
                ],

                const SizedBox(height: 20),
                if (req.isPending) ...[
                  QPrimaryButton(
                    label: tr('Принять изменения', 'Өзгерістерді қабылдау'),
                    isLoading: _loading,
                    icon: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _approve,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _reject,
                      icon: const Icon(Icons.close_rounded,
                          color: cRed, size: 19),
                      label: Text(tr('Вернуть — запросить причину', 'Қайтару — себеп сұрау'),
                          style: manrope(15, FontWeight.w700, color: cRed)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                ] else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: req.isApproved ? cGreenTint : cRedTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            req.isApproved
                                ? tr('Изменения приняты', 'Өзгерістер қабылданды')
                                : tr('Запрос возвращён', 'Сұраныс қайтарылды'),
                            style: manrope(14, FontWeight.w700,
                                color: req.isApproved
                                    ? cGreenDeep
                                    : const Color(0xFFB11A2B))),
                        if (req.reviewNote.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(req.reviewNote,
                              style: manrope(12.5, FontWeight.w500,
                                  color: cInk2, height: 1.4)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

String _statusLabel(StoreEditRequestModel r) {
  if (r.isApproved) return tr('Одобрено', 'Мақұлданды');
  if (r.isRejected) return tr('Отклонено', 'Қабылданбады');
  if (r.isCancelled) return tr('Отозвано', 'Кері қайтарылды');
  return tr('Ожидание', 'Күту');
}

String _statusTone(StoreEditRequestModel r) {
  if (r.isApproved) return 'green';
  if (r.isRejected) return 'red';
  if (r.isCancelled) return 'gray';
  return 'amber';
}

// ── Diff card (Было | Новое) ─────────────────────────────────────────────────────
class _DiffCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String oldValue;
  final String newValue;
  const _DiffCard({
    required this.label,
    required this.icon,
    required this.oldValue,
    required this.newValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(icon, color: cInk2, size: 16),
            const SizedBox(width: 8),
            Text(label.toUpperCase(),
                style: manrope(11.5, FontWeight.w800,
                    color: cInk2, letterSpacing: 0.5)),
          ]),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: cLine)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('БЫЛО', 'БҰРЫН'),
                          style: manrope(10, FontWeight.w700, color: cInk3)),
                      const SizedBox(height: 5),
                      Text(oldValue,
                          style: manrope(13.5, FontWeight.w600, color: cInk)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  color: cGreenTint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('НОВОЕ', 'ЖАҢА'),
                          style:
                              manrope(10, FontWeight.w700, color: cGreenDeep)),
                      const SizedBox(height: 5),
                      Text(newValue,
                          style: manrope(13.5, FontWeight.w800,
                              color: cGreenDeep)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
String _fmtDateTime(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
