import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

/// Курьер тіркелді, бірақ модератор әлі бекітпеді (немесе бұғаттады).
///
/// Тапсырыс тізімі мүлде көрсетілмейді — бекітілмеген курьер бөтен дүкеннің
/// мекенжайын, клиенттің телефонын көрмеуі керек (RPC де оны қайтармайды).
class CourierPendingScreen extends StatelessWidget {
  const CourierPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();
    final blocked = user.courierStatus == 'blocked';
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: blocked ? cRedTint : cGreenTint,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                    blocked
                        ? Icons.block_rounded
                        : Icons.hourglass_top_rounded,
                    color: blocked ? cRed : cGreen,
                    size: 42),
              ),
              const SizedBox(height: 22),
              Text(
                blocked
                    ? tr('Доступ приостановлен', 'Рұқсат тоқтатылды')
                    : tr('Ждём подтверждения', 'Растауды күтудеміз'),
                textAlign: TextAlign.center,
                style: manrope(21, FontWeight.w800, color: cInk),
              ),
              const SizedBox(height: 10),
              Text(
                blocked
                    ? tr('Модератор приостановил доступ к заказам. Свяжитесь с ним для уточнения.',
                        'Модератор тапсырыстарға рұқсатты тоқтатты. Нақтылау үшін онымен хабарласыңыз.')
                    : tr('Модератор проверит вашу заявку и откроет доступ к заказам. Обычно это занимает немного времени.',
                        'Модератор өтінішіңізді тексеріп, тапсырыстарға рұқсат ашады. Әдетте бұл ұзаққа созылмайды.'),
                textAlign: TextAlign.center,
                style:
                    manrope(14, FontWeight.w600, color: cInk2, height: 1.45),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cLine),
                ),
                child: Row(children: [
                  const Icon(Icons.location_city_outlined,
                      color: cInk3, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name,
                              style: manrope(14, FontWeight.w800, color: cInk)),
                          Text(
                              '${trValue(user.city)} · ${user.phone}',
                              style: manrope(12.5, FontWeight.w600,
                                  color: cInk3)),
                        ]),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: () => AuthService().signOut(),
                icon: const Icon(Icons.logout_rounded, size: 18, color: cInk3),
                label: Text(tr('Выйти', 'Шығу'),
                    style: manrope(14, FontWeight.w700, color: cInk3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
