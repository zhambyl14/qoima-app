import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime-ағынды үзілістерге төзімді етеді.
///
/// МАҢЫЗДЫ: нәтиже — broadcast, BehaviorSubject семантикасымен (жаңа тыңдаушы
/// соңғы мәнді бірден алады). SupabaseStreamBuilder да осылай істейді, сол
/// себепті бір ағынды бірнеше StreamBuilder бөлісе алады (мыс.
/// online_orders_screen үш жерде тыңдайды). Кәдімгі async*-пен ораса —
/// single-subscription болып, екінші тыңдаушы «already listened» қатесімен
/// құлайды да, тізім үнсіз бос көрінеді.
///
/// Мінез-құлық:
///  • RealtimeSubscribeException (арна қатесі: әлсіз желі, фоннан оралу)
///    UI-ға ЖЕТКІЗІЛМЕЙДІ — ағын тірі қалады (REST көшірмесі келе береді),
///    фонда өсетін кідіріспен (1с..15с) қайта жазыламыз.
///  • Ағын жабылып қалса (closed) — автоматты қайта қосылады.
///  • Басқа қателер (RLS, Postgrest, желі) тыңдаушыға сол күйі беріледі —
///    нақты ақауды жасырмау үшін.
Stream<T> retryStream<T>(Stream<T> Function() make) {
  final listeners = <MultiStreamController<T>>[];
  StreamSubscription<T>? sub;
  Timer? timer;
  var attempt = 0;
  T? last;
  var hasLast = false;

  late void Function() connect;

  void scheduleReconnect() {
    attempt++;
    timer?.cancel();
    timer = Timer(Duration(seconds: attempt < 15 ? attempt : 15), () {
      if (listeners.isNotEmpty) connect();
    });
  }

  connect = () {
    sub?.cancel();
    sub = make().listen(
      (value) {
        attempt = 0;
        last = value;
        hasLast = true;
        for (final l in List.of(listeners)) {
          l.add(value);
        }
      },
      onError: (Object e, StackTrace st) {
        if (e is RealtimeSubscribeException) {
          // Арна құлағанмен SupabaseStreamBuilder жабылмайды — REST дерегі
          // келе береді; қатені жұтып, фонда қайта қосылуды жоспарлаймыз.
          scheduleReconnect();
        } else {
          for (final l in List.of(listeners)) {
            l.addError(e, st);
          }
        }
      },
      onDone: () {
        if (listeners.isNotEmpty) scheduleReconnect();
      },
    );
  };

  return Stream<T>.multi((controller) {
    listeners.add(controller);
    if (hasLast) controller.add(last as T);
    controller.onCancel = () {
      listeners.remove(controller);
      if (listeners.isEmpty) {
        timer?.cancel();
        sub?.cancel();
        sub = null;
      }
    };
    if (sub == null) connect();
  });
}
