import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/report_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/login_screen.dart';

/// Контентке шағымдану sheet-і (App Store Guideline 1.2 — report mechanism).
///
/// Кез келген АВТОРИЗАЦИЯЛАНҒАН қолданушы шақыра алады; guest — логинге
/// бағытталады. [targetType]: 'product' | 'store' | 'review'.
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String targetName,
  String adminUid = '',
  String storeName = '',
}) async {
  final user = context.read<AppUser>();
  if (user.uid.isEmpty) {
    // Guest — алдымен кіру керек (шағым аноним болмауы үшін).
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Нужен вход', 'Кіру қажет'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Чтобы отправить жалобу, войдите в аккаунт.',
                'Шағым жіберу үшін аккаунтқа кіріңіз.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Войти', 'Кіру'),
                  style: manrope(14, FontWeight.w700, color: cGreen))),
        ],
      ),
    );
    if (goLogin == true && context.mounted) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetName: targetName,
      adminUid: adminUid,
      storeName: storeName,
      reporterName: user.name,
      reporterPhone: user.phone,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  final String targetType, targetId, targetName, adminUid, storeName;
  final String reporterName, reporterPhone;
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.adminUid,
    required this.storeName,
    required this.reporterName,
    required this.reporterPhone,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _service = ClientService();
  final _commentCtrl = TextEditingController();
  String? _reason;
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reason == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await _service.submitReport(
        targetType: widget.targetType,
        targetId: widget.targetId,
        targetName: widget.targetName,
        reason: _reason!,
        comment: _commentCtrl.text,
        adminUid: widget.adminUid,
        storeName: widget.storeName,
        reporterName: widget.reporterName,
        reporterPhone: widget.reporterPhone,
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Жалоба отправлена. Мы рассмотрим её в ближайшее время.',
            'Шағым жіберілді. Жақын арада қараймыз.')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Не удалось отправить жалобу', 'Шағым жіберілмеді')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flag_outlined, color: cRed, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Пожаловаться', 'Шағымдану'),
                      style: manrope(17, FontWeight.w800, color: cInk)),
                  Text(
                    '${reportTargetLabel(widget.targetType)} · ${widget.targetName}',
                    style: manrope(12.5, FontWeight.w500, color: cInk3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          // Себептер
          ...kReportReasons.map((key) {
            final selected = _reason == key;
            return GestureDetector(
              onTap: () => setState(() => _reason = key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? cGreenTint : cBg,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: selected ? cGreen : cLine, width: 1.5),
                ),
                child: Row(children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected ? cGreen : cInk3,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(reportReasonLabel(key),
                        style: manrope(14, FontWeight.w600,
                            color: selected ? cGreenDeep : cInk)),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 6),
          // Түсіндірме (қалау бойынша)
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 500,
            style: manrope(14, FontWeight.w500, color: cInk),
            cursorColor: cGreen,
            decoration: InputDecoration(
              hintText: tr('Опишите проблему (необязательно)',
                  'Мәселені сипаттаңыз (міндетті емес)'),
              hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
              filled: true,
              fillColor: cBg,
              counterStyle: manrope(11, FontWeight.w500, color: cInk3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: cGreen, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          QPrimaryButton(
            label: _sending
                ? tr('Отправка...', 'Жіберілуде...')
                : tr('Отправить жалобу', 'Шағым жіберу'),
            onPressed: (_reason != null && !_sending) ? _send : null,
            height: 52,
          ),
        ]),
      ),
    );
  }
}
