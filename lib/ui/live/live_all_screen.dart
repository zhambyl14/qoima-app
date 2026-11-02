import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_user.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/services/follow_service.dart';
import '../../theme/qoima_design.dart';
import '../client/client_product_card.dart' show ClientEmptyState;
import '../shared/error_view.dart';
import 'live_stream_card.dart';

/// «Барлық эфирлер»: қазір тірі БАРЛЫҚ эфир (0084). Басты бетте тек жазылған
/// дүкендердің эфирі қалады, қалғаны осында. Жазылғандар алдымен тұрады
/// (сервер осылай сұрыптайды). Төмен тартып жаңартуға болады; ашық тұрғанда
/// 30 с сайын өздігінен жаңарады. Эфирді басса — бар көрермен ашылады.
class LiveAllScreen extends StatefulWidget {
  /// Тек тест үшін.
  final FollowService? follow;
  const LiveAllScreen({super.key, this.follow});

  @override
  State<LiveAllScreen> createState() => _LiveAllScreenState();
}

class _LiveAllScreenState extends State<LiveAllScreen> {
  FollowService get _follow => widget.follow ?? FollowService.instance;

  List<HomeLiveSession>? _items;
  Object? _error;
  bool _loading = false;
  Timer? _timer;

  bool get _flagOn => FeatureFlags.instance.isOn(FeatureFlags.liveShopping);

  @override
  void initState() {
    super.initState();
    FeatureFlags.instance.addListener(_onFlags);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    FeatureFlags.instance.removeListener(_onFlags);
    _timer?.cancel();
    super.dispose();
  }

  void _onFlags() {
    if (mounted) setState(() {});
    _load();
  }

  Future<void> _load() async {
    // Гостьта RLS бос тізім береді — сұрамаймыз, нұсқау көрсетеміз.
    if (_loading || !mounted || !_flagOn || AppUser.current.uid.isEmpty) return;
    _loading = true;
    try {
      // 100 — серверде рұқсат етілген жоғарғы шек.
      final list = await _follow.liveSessionsForHome(limit: 100);
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } catch (e) {
      // Тізім бұрыннан көрініп тұрса, 30 с таймері қатесі оны бұзбасын.
      if (mounted && _items == null) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Все эфиры', 'Барлық эфирлер'),
          subtitle:
              tr('Прямые трансляции магазинов', 'Дүкендердің тікелей эфирлері'),
          showBack: true,
          compact: true,
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (!_flagOn) {
      return ClientEmptyState(
          icon: Icons.sensors_off_rounded,
          message: tr('Функция временно отключена', 'Функция уақытша өшірулі'));
    }
    if (AppUser.current.uid.isEmpty) {
      return ClientEmptyState(
          icon: Icons.lock_outline_rounded,
          message: tr(
              'Войдите, чтобы смотреть эфиры', 'Эфирлерді көру үшін кіріңіз'));
    }
    if (_error != null && _items == null) {
      return AppErrorView(
          error: _error,
          onRetry: () async {
            setState(() => _error = null);
            await _load();
          });
    }
    final items = _items;
    if (items == null) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    final followed = items.where((e) => e.followed).toList();
    final others = items.where((e) => !e.followed).toList();
    return RefreshIndicator(
      color: cGreen,
      onRefresh: _load,
      child: items.isEmpty
          // Бос күйде де төмен тарту жұмыс істеуі үшін айналатын тізім.
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: ClientEmptyState(
                      icon: Icons.sensors_off_rounded,
                      message: tr('Сейчас нет прямых эфиров',
                          'Қазір тікелей эфир жоқ')),
                ),
              ],
            )
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (followed.isNotEmpty) ...[
                  _label(tr('Ваши подписки', 'Жазылғандарыңыз')),
                  _grid(followed),
                ],
                if (others.isNotEmpty) ...[
                  _label(followed.isEmpty
                      ? tr('Сейчас в эфире', 'Қазір эфирде')
                      : tr('Другие эфиры', 'Басқа эфирлер')),
                  _grid(others),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
    );
  }

  Widget _label(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(text, style: manrope(15.5, FontWeight.w800, color: cInk)),
        ),
      );

  Widget _grid(List<HomeLiveSession> list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => LiveStreamCard(
              key: ValueKey('live-${list[i].session.id}'),
              session: list[i].session,
              storeName: list[i].storeName,
              fallbackImage: list[i].storeLogoUrl,
              width: null,
            ),
            childCount: list.length,
          ),
        ),
      );
}
