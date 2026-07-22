import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../core/banks.dart';
import '../../core/card_utils.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../theme/qoima_design.dart';
import 'reject_reason_sheet.dart';

import '../../core/lang.dart';
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
        reviewedBy: Supabase.instance.client.auth.currentUser!.id,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Магазин «${req.shopName}» одобрен', '«${req.shopName}» дүкені мақұлданды')),
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
      title: tr('Отклонение заявки', 'Өтінімді қабылдамау'),
      subtitle: req.shopName,
    );
    if (note == null || !mounted) return;
    setState(() => _loading = true);
    try {
      await _repo.rejectRequest(
        requestId: req.id,
        reviewedBy: Supabase.instance.client.auth.currentUser!.id,
        reviewNote: note,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Заявка отклонена', 'Өтінім қабылданбады')),
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
          title: tr('Заявка #$idShort', 'Өтінім #$idShort'),
          subtitle: '${req.shopName} · ${_fmtDate(req.createdAt)}',
          showBack: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QSecLabel(tr('О владельце', 'Иесі туралы')),
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
                                    ? tr('Телефон не указан', 'Телефон көрсетілмеген')
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
                        tr('ИИН / БИН', 'ЖСН / БСН'),
                        req.ownerIin.isEmpty ? '—' : req.ownerIin),
                    const SizedBox(height: 8),
                    _InfoRow(tr('Дата подачи', 'Берілген күні'), _fmtDateTime(req.createdAt)),
                  ]),
                ),

                const SizedBox(height: 18),
                QSecLabel(tr('О магазине', 'Дүкен туралы')),
                QCard(
                  child: Column(children: [
                    _InfoRow(tr('Название', 'Атауы'), req.shopName),
                    const SizedBox(height: 8),
                    _InfoRow(tr('Город', 'Қала'), req.city.isEmpty ? '—' : trValue(req.city)),
                    const SizedBox(height: 8),
                    _InfoRow('Категория',
                        req.category.isEmpty ? '—' : trValue(req.category)),
                    if (req.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(height: 1, color: cLine),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(tr('Описание', 'Сипаттама'),
                            style: manrope(12.5, FontWeight.w600, color: cInk3)),
                      ),
                      const SizedBox(height: 4),
                      Text(req.description,
                          style: manrope(13.5, FontWeight.w500,
                              color: cInk2, height: 1.45)),
                    ],
                  ]),
                ),

                if (req.bankQrs.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  QSecLabel(tr('Приём оплаты — QR банков', 'Төлем қабылдау — банк QR-лары')),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: cGreenTint,
                        borderRadius: BorderRadius.circular(14)),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: orderedBankQrs(req.bankQrs)
                          .map((e) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: cLine)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.qr_code_2_rounded,
                                      size: 14, color: cGreenDeep),
                                  const SizedBox(width: 5),
                                  Text(bankName(e.key),
                                      style: manrope(12, FontWeight.w700,
                                          color: cInk)),
                                ]),
                              ))
                          .toList(),
                    ),
                  ),
                ] else if (req.cardNumber.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  QSecLabel(tr('Финансы — карта', 'Қаржы — карта')),
                  _CardInfoCard(req: req),
                ],

                const SizedBox(height: 18),

                if (req.isPending) ...[
                  QPrimaryButton(
                    label: tr('Одобрить магазин', 'Дүкенді мақұлдау'),
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
                      child: Text(tr('Отклонить', 'Қабылдамау'),
                          style: manrope(15, FontWeight.w700, color: cRed)),
                    ),
                  ),
                ] else if (req.isApproved) ...[
                  _StatusBanner(
                    color: cGreen,
                    bg: cGreenTint,
                    icon: Icons.check_circle_rounded,
                    text:
                        tr('Одобрено · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}', 'Мақұлданды · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}'),
                  ),
                ] else if (req.isRejected) ...[
                  _StatusBanner(
                    color: const Color(0xFFB11A2B),
                    bg: cRedTint,
                    icon: Icons.cancel_rounded,
                    text:
                        tr('Отклонено · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}', 'Қабылданбады · ${req.reviewedAt != null ? _fmtDate(req.reviewedAt!) : ''}'),
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
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            QPill(tr('БИН проверен', 'БСН тексерілді'),
                tone: 'green',
                icon: Icon(Icons.check_rounded, color: cGreenDeep, size: 13)),
            QPill(tr('Владелец совпадает', 'Иесі сәйкес келеді'),
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
