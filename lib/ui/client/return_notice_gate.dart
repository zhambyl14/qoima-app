import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_user.dart';
import '../../core/feature_flags.dart';
import '../../data/models/order_model.dart';
import 'return_notice_sheet.dart';

/// ClientShell-ге оралады: тауар қолға тиген тапсырыстың қайтару шарттарын бір
/// рет көрсетеді (0082). GuestShell-де жоқ, сондықтан қонақ мұны ешқашан көрмейді.
///
/// Толық orders ағынын әдейі ұстамаймыз: сұрақ сирек және жеңіл, сондықтан үш
/// оқиғада (ашылу, қосымшаға оралу, тапсырыстың realtime жаңаруы) бір сұраныс
/// жеткілікті. Бәрі үнсіз: хабарлама shell-ді ешқашан бұзбауы керек.
class ReturnNoticeGate extends StatefulWidget {
  final Widget child;
  const ReturnNoticeGate({super.key, required this.child});

  @override
  State<ReturnNoticeGate> createState() => _ReturnNoticeGateState();
}

class _ReturnNoticeGateState extends State<ReturnNoticeGate>
    with WidgetsBindingObserver {
  static const _batch = 5;
  static const _window = Duration(days: 30);
  static const _columns =
      'id,store_name,order_number,items,delivery_mode,order_type,return_policy,status,completed_at';

  /// Осы сессияда көрсетілгендер. ack сәтсіз болса да қайта шықпайды — келесі
  /// ашқанда ғана (realtime мен resume бірге келгенде де екі рет шықпайды).
  final Set<String> _shown = {};

  RealtimeChannel? _channel;
  bool _flagOn = false;
  bool _busy = false;
  bool _again = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FeatureFlags.instance.addListener(_syncFlag);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFlag());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FeatureFlags.instance.removeListener(_syncFlag);
    _dropChannel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Фондағы оқиғалар realtime-нан өтіп кетуі мүмкін, сол үшін қайта сұраймыз.
    _flagOn ? _check() : _syncFlag();
  }

  /// Жалауша жүктелгенше isOn false береді. Оны біржола «өшік» деп санамаймыз:
  /// жауап келгенде listener осы жерге қайта кіреді.
  void _syncFlag() {
    if (!mounted) return;
    final on = FeatureFlags.instance.isOn(FeatureFlags.returnNotice);
    if (on == _flagOn) return;
    _flagOn = on;
    if (on) {
      _openChannel();
      _check();
    } else {
      _dropChannel();
    }
  }

  void _openChannel() {
    try {
      final uid = _clientUid;
      if (uid == null || _channel != null) return;
      final sb = Supabase.instance.client;
      _channel = sb
          .channel('return_notice_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'client_uid',
              value: uid,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              if (row['status'] != OrderModel.statusCompleted) return;
              // Өз ack-іміздің жаңаруы да осында келеді — артық сұранбаймыз.
              if (row['return_notice_ack_at'] != null) return;
              _check();
            },
          )
          .subscribe();
    } catch (_) {
      // Realtime болмаса да, ашылу мен resume арқылы хабарлама шығады.
    }
  }

  void _dropChannel() {
    final ch = _channel;
    _channel = null;
    if (ch == null) return;
    try {
      Supabase.instance.client.removeChannel(ch);
    } catch (_) {}
  }

  String? get _clientUid {
    final user = AppUser.current;
    return user.isLoaded && user.isClient ? user.uid : null;
  }

  Future<List<OrderModel>> _fetchPending(String uid) async {
    final since = DateTime.now().toUtc().subtract(_window).toIso8601String();
    final rows = await Supabase.instance.client
        .from('orders')
        .select(_columns)
        .eq('client_uid', uid)
        .eq('status', OrderModel.statusCompleted)
        .isFilter('return_notice_ack_at', null)
        .not('return_policy', 'is', null)
        .gte('completed_at', since)
        .order('completed_at', ascending: true)
        .limit(_batch);
    return rows.map(OrderModel.fromMap).toList();
  }

  /// Бір уақытта бір ғана айналым және бір ғана парақ. Парақ ашық тұрғанда
  /// келген оқиға [_again] белгісін қояды да, парақ жабылған соң тексеріледі.
  Future<void> _check() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      bool repeat;
      do {
        _again = false;
        final uid = _clientUid;
        if (!mounted || !_flagOn || uid == null) return;
        final orders = await _fetchPending(uid);
        var showedAny = false;
        for (final order in orders) {
          if (!mounted || !_flagOn) return;
          if (!_shown.add(order.id)) continue;
          showedAny = true;
          await showReturnNoticeSheet(context, order);
        }
        // Топтама толы болса, артында тағы тапсырыс қалуы мүмкін. Жаңа ештеңе
        // көрсетілмесе тоқтаймыз: ack өтпеген тапсырыстар циклге түсірмейді.
        repeat = _again || (showedAny && orders.length >= _batch);
      } while (repeat);
    } catch (_) {
      // Әдейі үнсіз: келесі оқиғада қайта тырысамыз.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
