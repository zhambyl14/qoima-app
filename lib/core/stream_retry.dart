import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime-ағынды желі үзілістеріне төзімді етеді: арна қатесінде
/// (RealtimeSubscribeException — әлсіз 4G, қайта қосылу, арна churn)
/// қатені экранға шығармай, өсетін кідіріспен қайта жазыламыз.
/// Басқа қателер (RLS, Postgrest т.б.) сол күйі жоғары лақтырылады —
/// нақты конфигурация ақауын жасырмау үшін.
Stream<T> retryStream<T>(Stream<T> Function() make) async* {
  var attempt = 0;
  while (true) {
    try {
      await for (final value in make()) {
        attempt = 0; // сәтті дерек келді — кідірісті нөлдейміз
        yield value;
      }
      return; // ағын қалыпты жабылды
    } on RealtimeSubscribeException {
      attempt++;
      await Future.delayed(Duration(seconds: attempt < 15 ? attempt : 15));
    }
  }
}
