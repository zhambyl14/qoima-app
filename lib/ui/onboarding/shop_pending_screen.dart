import 'package:flutter/material.dart';
import '../../data/models/shop_request_model.dart';
import '../../theme/qoima_design.dart';

/// Заявка жіберілгеннен кейінгі күту экраны. Деректерді AdminApprovalGate-тегі
/// StreamBuilder-ден алады (req). Статус 'approved'-ке ауысқанда gate-тің өзі
/// дүкенді provision етіп, AdminShell-ге өткізеді.
class ShopPendingScreen extends StatelessWidget {
  final ShopRequestModel req;
  final VoidCallback? onCancel;

  const ShopPendingScreen({super.key, required this.req, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Заявка отправлена',
          subtitle: 'Открытие магазина',
          showBack: onCancel != null,
          onBack: onCancel,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                      color: cAmberTint, shape: BoxShape.circle),
                  child: const Icon(Icons.access_time_rounded,
                      color: cAmber, size: 50),
                ),
                const SizedBox(height: 20),
                Text('Заявка на рассмотрении',
                    style: manrope(22, FontWeight.w800,
                        color: cInk, letterSpacing: -0.4),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Модератор маркетплейса проверит данные вашего магазина '
                  'и уведомит вас. Обычно это занимает 1–2 рабочих дня.',
                  style: manrope(14, FontWeight.w500, color: cInk2, height: 1.45),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Summary card
                QCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Row(children: [
                      QIconTile(
                        icon: const Icon(Icons.store_outlined,
                            color: cGreen, size: 20),
                        tone: 'green',
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(req.shopName,
                                style: manrope(15, FontWeight.w800, color: cInk)),
                            Text(
                                '${req.category}${req.city.isNotEmpty ? ' · ${req.city}' : ''}',
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk3)),
                          ],
                        ),
                      ),
                      const QPill('Ожидание',
                          tone: 'amber',
                          icon: Icon(Icons.access_time_rounded,
                              size: 13, color: Color(0xFF9A6A06))),
                    ]),
                  ]),
                ),

                const SizedBox(height: 24),

                // 3-step progress
                _StepRow(
                  icon: Icons.check_circle_rounded,
                  label: 'Заявка отправлена',
                  state: _StepState.done,
                ),
                _StepConnector(active: true),
                _StepRow(
                  icon: Icons.access_time_rounded,
                  label: 'Модератор проверяет',
                  state: _StepState.active,
                ),
                _StepConnector(active: false),
                _StepRow(
                  icon: Icons.storefront_rounded,
                  label: 'Магазин откроется',
                  state: _StepState.future,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

enum _StepState { done, active, future }

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final _StepState state;
  const _StepRow(
      {required this.icon, required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color bg, fg, textColor;
    switch (state) {
      case _StepState.done:
        bg = cGreenTint;
        fg = cGreen;
        textColor = cInk;
        break;
      case _StepState.active:
        bg = cAmberTint;
        fg = cAmber;
        textColor = cInk;
        break;
      case _StepState.future:
        bg = cLine2;
        fg = cInk3;
        textColor = cInk3;
        break;
    }
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 20),
      ),
      const SizedBox(width: 14),
      Text(label,
          style: manrope(14.5,
              state == _StepState.future ? FontWeight.w500 : FontWeight.w700,
              color: textColor)),
    ]);
  }
}

class _StepConnector extends StatelessWidget {
  final bool active;
  const _StepConnector({required this.active});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Container(
        width: 2,
        height: 22,
        color: active ? cGreen : cLine,
      ),
    );
  }
}
