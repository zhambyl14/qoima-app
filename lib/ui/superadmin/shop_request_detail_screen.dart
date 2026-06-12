import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/card_utils.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../theme/qoima_design.dart';
import 'reject_reason_sheet.dart';

/// Superadmin — заявка детальі. Бекіту / бас тарту (себебімен).
class ShopRequestDetailScreen extends StatefulWidget {
  final ShopRequestModel req;
  const ShopRequestDetailScreen({super.key, required this.req});

  @override
  State<ShopRequestDetailScreen> createState() =>
      _ShopRequestDetailScreenState();
}

class _ShopRequestDetailScreenState extends State<ShopRequestDetailScreen> {
  final _repo = ShopRequestRepository();
  bool _loading = false;

  ShopRequestModel get req => widget.req;

  Future<void> _approve() async {
    setState(() => _loading = true);
    try {
      await _repo.approveRequest(
        requestId: req.id,
        reviewedBy: FirebaseAuth.instance.currentUser!.uid,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Магазин «${req.shopName}» одобрен'),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _reject() async {
    final note = await showRejectReasonSheet(
      context,
      title: 'Отклонение заявки',
      subtitle: req.shopName,
    );
    if (note == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await _repo.rejectRequest(
        requestId: req.id,
        reviewedBy: FirebaseAuth.instance.currentUser!.uid,
        reviewNote: note,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Заявка отклонена'),
          backgroundColor: cInk,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final idShort =
        req.id.length >= 6 ? req.id.substring(0, 6).toUpperCase() : req.id;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Заявка #$idShort',
          subtitle: '${req.shopName} · ${_fmtDate(req.createdAt)}',
          showBack: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const QSecLabel('О владельце'),
                QCard(
                  child: Column(children: [
                    Row(children: [
                      QIconTile(
                        icon: const Icon(Icons.person_outline_rounded,
                            color: cGreen, size: 20),
                        tone: 'green',
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(req.ownerName.isEmpty ? '—' : req.ownerName,
                                style:
                                    manrope(15, FontWeight.w800, color: cInk)),
                            Text(
                                req.ownerPhone.isEmpty
                                    ? 'Телефон не указан'
                                    : req.ownerPhone,
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk3)),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Container(height: 1, color: cLine),
                    const SizedBox(height: 12),
                    _InfoRow(
                        'ИИН / БИН',
                        req.ownerIin.isEmpty ? '—' : req.ownerIin),
                    const SizedBox(height: 8),
                    _InfoRow('Дата подачи', _fmtDateTime(req.createdAt)),
                  ]),
                ),

                const SizedBox(height: 18),
                const QSecLabel('О магазине'),
                QCard(
                  child: Column(children: [
                    _InfoRow('Название', req.shopName),
                    const SizedBox(height: 8),
                    _InfoRow('Город', req.city.isEmpty ? '—' : req.city),
                    const SizedBox(height: 8),
                    _InfoRow('Категория',
                        req.category.isEmpty ? '—' : req.category),
                    if (req.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(height: 1, color: cLine),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Описание',
                            style: manrope(12.5, FontWeight.w600, color: cInk3)),
                      ),
                      const SizedBox(height: 4),
                      Text(req.description,
                          style: manrope(13.5, FontWeight.w500,
                              color: cInk2, height: 1.45)),
                    ],
                  ]),
                ),

                if (req.cardNumber.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const QSecLabel('Финансы — карта'),
                  _CardInfoCard(req: req),
                ],

                const SizedBox(height: 18),

                if (req.isPending) ...[
                  QPrimaryButton(
                    label: 'Одобрить магазин',
                    isLoading: _loading,
                    icon: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _approve,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cRed,
                        side: const BorderSide(color: cRed),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text('Отклонить',
                          style: manrope(15, FontWeight.w700, color: cRed)),
                    ),
                  ),
                ] else if (req.isApproved) ...[
                  _StatusBanner(
                    color: cGreen,
                    bg: cGreenTint,
                    icon: Icons.check_circle_rounded,
                    text:
                        'Одобрено · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}',
                  ),
                ] else if (req.isRejected) ...[
                  _StatusBanner(
                    color: const Color(0xFFB11A2B),
                    bg: cRedTint,
                    icon: Icons.cancel_rounded,
                    text:
                        'Отклонено · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}',
                    note: req.reviewNote,
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Финансы — карта ──────────────────────────────────────────────────────────────
class _CardInfoCard extends StatelessWidget {
  final ShopRequestModel req;
  const _CardInfoCard({required this.req});

  @override
  Widget build(BuildContext context) {
    final holderBank = [
      if (req.cardBank.isNotEmpty) req.cardBank,
      if (req.cardHolder.isNotEmpty) req.cardHolder,
    ].join(' · ');
    return QCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [cAmber, Color(0xFFF5C451)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Center(
              child: Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatCardDisplay(req.cardNumber),
                    style: manrope(15.5, FontWeight.w800,
                        color: cInk, letterSpacing: 1.0)),
                if (holderBank.isNotEmpty)
                  Text(holderBank,
                      style: manrope(12, FontWeight.w600, color: cInk3)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            QPill('БИН проверен',
                tone: 'green',
                icon: Icon(Icons.check_rounded, color: cGreenDeep, size: 13)),
            QPill('Владелец совпадает',
                tone: 'green',
                icon: Icon(Icons.check_rounded, color: cGreenDeep, size: 13)),
          ],
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: manrope(12.5, FontWeight.w500, color: cInk3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: manrope(13.5, FontWeight.w700, color: cInk)),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final Color bg;
  final IconData icon;
  final String text;
  final String? note;
  const _StatusBanner({
    required this.color,
    required this.bg,
    required this.icon,
    required this.text,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: manrope(14, FontWeight.w700, color: color)),
            ),
          ]),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note!,
                style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';
String _fmtDateTime(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
