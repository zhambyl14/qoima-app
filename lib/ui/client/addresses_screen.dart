import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import 'address_map_picker_screen.dart';

import '../../core/lang.dart';
class AddressesScreen extends StatelessWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = ClientService();
    return Scaffold(
      backgroundColor: cBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, service),
        backgroundColor: cGreen,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(tr('Добавить', 'Қосу'), style: manrope(14, FontWeight.w700, color: Colors.white)),
      ),
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Text(tr('Адреса доставки', 'Жеткізу мекенжайлары'),
                    style: manrope(20, FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: service.watchAddresses(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: cGreen));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_off_outlined,
                        size: 60, color: cInk3.withValues(alpha: 0.35)),
                    const SizedBox(height: 14),
                    Text(tr('Нет сохранённых адресов', 'Сақталған мекенжай жоқ'),
                        style: manrope(16, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Text(tr('Нажмите «Добавить» чтобы сохранить адрес', 'Мекенжай сақтау үшін «Қосу» басыңыз'),
                        style: manrope(13, FontWeight.w500, color: cInk3)),
                  ]),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final addr = items[i];
                  final label = addr['label'] as String? ?? '';
                  final address = addr['address'] as String? ?? '';
                  final id = addr['id'] as String;
                  final hasGeo = addr['lat'] != null && addr['lng'] != null;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: cSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cLine),
                      boxShadow: kShadowSm,
                    ),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on_outlined,
                            color: cGreen, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (label.isNotEmpty)
                            Text(label,
                                style: manrope(14, FontWeight.w700, color: cInk)),
                          Text(address,
                              style: manrope(12.5, FontWeight.w500, color: cInk2)),
                          if (hasGeo) ...[
                            const SizedBox(height: 3),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.map_rounded, size: 12, color: cGreen),
                              const SizedBox(width: 3),
                              Text(tr('Точка на карте указана', 'Картадағы нүкте белгіленген'),
                                  style: manrope(11, FontWeight.w600, color: cGreen)),
                            ]),
                          ],
                        ]),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              title: Text(tr('Удалить адрес?', 'Мекенжайды өшіру керек пе?'),
                                  style: manrope(16, FontWeight.w700, color: cInk)),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(tr('Отмена', 'Болдырмау'),
                                        style: manrope(14, FontWeight.w600,
                                            color: cInk2))),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text(tr('Удалить', 'Өшіру'),
                                        style: manrope(14, FontWeight.w600,
                                            color: cRed))),
                              ],
                            ),
                          );
                          if (ok == true) service.deleteAddress(id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline_rounded,
                              color: cInk3, size: 20),
                        ),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  void _showAddDialog(BuildContext context, ClientService service) {
    final city = context.read<AppUser>().city;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddAddressSheet(service: service, initialCity: city),
    );
  }
}

class _AddAddressSheet extends StatefulWidget {
  final ClientService service;
  final String initialCity;
  const _AddAddressSheet({required this.service, required this.initialCity});

  @override
  State<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<_AddAddressSheet> {
  final _labelCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  LatLng? _picked;
  bool _saving = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final point = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressMapPickerScreen(
            initialCity: widget.initialCity, initialPoint: _picked),
      ),
    );
    if (point != null && mounted) setState(() => _picked = point);
  }

  Future<void> _save() async {
    if (_addrCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.service.addAddress(
        label: _labelCtrl.text,
        address: _addrCtrl.text,
        lat: _picked?.latitude,
        lng: _picked?.longitude,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Не удалось сохранить адрес', 'Мекенжайды сақтау мүмкін болмады')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Новый адрес', 'Жаңа мекенжай'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
                hintText: tr('Название (Дом, Работа...)', 'Атауы (Үй, Жұмыс...)'),
                prefixIcon: Icon(Icons.label_outline)),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addrCtrl,
            decoration: InputDecoration(
                hintText: tr('Полный адрес', 'Толық мекенжай'),
                prefixIcon: Icon(Icons.location_on_outlined)),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
          ),
          const SizedBox(height: 12),

          // ── Картадан нүкте белгілеу (міндетті емес, бірақ ұсынылады) ─────
          GestureDetector(
            onTap: _pickOnMap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                color: _picked != null ? cGreenTint : cBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _picked != null ? cGreen.withValues(alpha: 0.4) : cLine),
              ),
              child: Row(children: [
                Icon(_picked != null ? Icons.check_circle_rounded : Icons.map_outlined,
                    size: 19, color: _picked != null ? cGreen : cInk2),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      _picked != null
                          ? tr('Точка на карте указана', 'Картадағы нүкте белгіленген')
                          : tr('Указать точку на карте (рекомендуем)',
                              'Картадан нүкте белгілеу (ұсынылады)'),
                      style: manrope(12.5, FontWeight.w700,
                          color: _picked != null ? cGreenDeep : cInk2)),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: _picked != null ? cGreen : cInk3),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
                tr('Так мы сможем показать вам ближайшие магазины',
                    'Осылай сізге ең жақын дүкендерді көрсете аламыз'),
                style: manrope(11, FontWeight.w500, color: cInk3)),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(tr('Сохранить', 'Сақтау'), style: manrope(15, FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
