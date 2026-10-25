import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/registry_model.dart';
import '../../../data/services/registry_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/error_view.dart';
import 'registry_edit_screen.dart';

/// «Той тілек тізімі» — менің тізімдерім.
///
/// Тізім realtime stream-мен келеді (initState-те бір рет жазылады), ал
/// прогресс сандары (алынды/барлығы) бөлек RPC-мен — қонақтардың кімдігі
/// иесіне ЕШҚАШАН көрінбейді (тосын сый).
class MyRegistriesScreen extends StatefulWidget {
  const MyRegistriesScreen({super.key});

  @override
  State<MyRegistriesScreen> createState() => _MyRegistriesScreenState();
}

class _MyRegistriesScreenState extends State<MyRegistriesScreen> {
  final _service = RegistryService();
  StreamSubscription<List<GiftRegistry>>? _sub;
  List<GiftRegistry> _registries = const [];
  Map<String, RegistrySummary> _summaries = const {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    _sub = _service.watchMyRegistries().listen((list) {
      if (!mounted) return;
      setState(() {
        _registries = list;
        _loading = false;
      });
      _loadSummaries();
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    });
  }

  Future<void> _loadSummaries() async {
    try {
      final s = await _service.getMySummaries();
      if (mounted) setState(() => _summaries = s);
    } catch (_) {
      // Прогресс қосымша ақпарат — қате болса карточка сандарсыз көрсетіледі.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _open([GiftRegistry? r]) async {
    HapticFeedback.selectionClick();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RegistryEditScreen(registry: r)),
    );
    if (mounted) _loadSummaries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Список желаний', 'Той тілек тізімі'),
          subtitle: tr('Подарки к вашему празднику', 'Мерекеңізге сыйлықтар'),
          showBack: true,
        ),
        Expanded(child: _body()),
      ]),
      bottomNavigationBar: ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (context, _) {
          final on = FeatureFlags.instance.isOn(FeatureFlags.giftRegistry);
          // Өшік болса жаңа тізім жасалмайды (сервер де 'feature_disabled' береді).
          if (!on) return const SizedBox.shrink();
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: QPrimaryButton(
                label: tr('Создать список', 'Тізім жасау'),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                onPressed: () => _open(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_error != null) {
      return AppErrorView(error: _error, onRetry: () async => _listen());
    }
    if (_registries.isEmpty) return const _EmptyIdea();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _registries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = _registries[i];
        return _RegistryCard(
          registry: r,
          summary: _summaries[r.id],
          onTap: () => _open(r),
        );
      },
    );
  }
}

class _RegistryCard extends StatelessWidget {
  final GiftRegistry registry;
  final RegistrySummary? summary;
  final VoidCallback onTap;
  const _RegistryCard(
      {required this.registry, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = registry;
    final s = summary ?? const RegistrySummary();
    final left = r.daysLeft;
    final countdown = registryCountdownText(r.eventDate);
    return QCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(kR20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cGreenTint,
                  borderRadius: BorderRadius.circular(kR16),
                ),
                child: Text(RegistryOccasion.emoji(r.occasion),
                    style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: manrope(16, FontWeight.w800, color: cInk)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          RegistryOccasion.label(r.occasion),
                          if (r.eventDate != null)
                            registryDateText(r.eventDate),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(12.5, FontWeight.w600, color: cInk3),
                      ),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: cInk3),
            ]),
            const SizedBox(height: 14),
            // Прогресс: алынған сыйлықтар / қалағандар.
            ClipRRect(
              borderRadius: BorderRadius.circular(kRPill),
              child: LinearProgressIndicator(
                value: s.progress,
                minHeight: 8,
                backgroundColor: cLine2,
                valueColor: const AlwaysStoppedAnimation(cGreen),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              QPill(
                s.itemsCount == 0
                    ? tr('Пока пусто', 'Әзірге бос')
                    : tr('${s.qtyTaken} из ${s.qtyTotal} выбрано',
                        '${s.qtyTaken} / ${s.qtyTotal} таңдалды'),
                tone: s.qtyTotal > 0 && s.qtyTaken >= s.qtyTotal
                    ? 'green'
                    : 'gray',
              ),
              QPill(tr('${s.itemsCount} товаров', '${s.itemsCount} тауар'),
                  tone: 'blue'),
              if (countdown.isNotEmpty)
                QPill(countdown,
                    tone: (left != null && left < 0)
                        ? 'gray'
                        : (left != null && left <= 7 ? 'amber' : 'green')),
              if (!r.isActive) QPill(tr('Закрыт', 'Жабық'), tone: 'red'),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Бос күй: идеяны түсіндіреді.
class _EmptyIdea extends StatelessWidget {
  const _EmptyIdea();

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            QIconTile(icon: Icon(icon, color: cGreen, size: 20), size: 40),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: manrope(13.5, FontWeight.w600, color: cInk2))),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(shape: BoxShape.circle, color: cGreenTint),
            child: const Text('🎁', style: TextStyle(fontSize: 46)),
          ),
        ),
        const SizedBox(height: 18),
        Text(
            tr('Пусть гости знают, что подарить',
                'Тойға не сыйлау керегін қонақтар білсін'),
            textAlign: TextAlign.center,
            style: manrope(19, FontWeight.w800, color: cInk)),
        const SizedBox(height: 8),
        Text(
            tr('Соберите список желаемых товаров и поделитесь ссылкой — никто не подарит одно и то же.',
                'Қалаған тауарларыңыздан тізім жасап, сілтемені бөлісіңіз — ешкім бірдей сыйлық әкелмейді.'),
            textAlign: TextAlign.center,
            style: manrope(13.5, FontWeight.w500, color: cInk3, height: 1.4)),
        const SizedBox(height: 24),
        step(
            Icons.add_circle_outline_rounded,
            tr('Создайте список и добавляйте товары со страницы любого товара',
                'Тізім жасап, кез келген тауар бетінен тауар қосыңыз')),
        step(
            Icons.share_rounded,
            tr('Поделитесь ссылкой с гостями',
                'Сілтемені қонақтарға жіберіңіз')),
        step(
            Icons.card_giftcard_rounded,
            tr('Гость выбирает подарок — он резервируется за ним',
                'Қонақ сыйлық таңдайды — ол соған брондалады')),
        step(
            Icons.check_circle_outline_rounded,
            tr('После оплаты подарок отмечается как купленный',
                'Төлемнен кейін сыйлық «сатып алынды» болып белгіленеді')),
      ],
    );
  }
}
