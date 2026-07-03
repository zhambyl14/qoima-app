import 'package:flutter/material.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

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
        label: Text('Добавить', style: manrope(14, FontWeight.w700, color: Colors.white)),
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
                Text('Адреса доставки',
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
                    Text('Нет сохранённых адресов',
                        style: manrope(16, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Text('Нажмите «Добавить» чтобы сохранить адрес',
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
                        ]),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                              title: Text('Удалить адрес?',
                                  style: manrope(16, FontWeight.w700, color: cInk)),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text('Отмена',
                                        style: manrope(14, FontWeight.w600,
                                            color: cInk2))),
                                TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('Удалить',
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
    final labelCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Новый адрес',
                style: manrope(17, FontWeight.w800, color: cInk)),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                  hintText: 'Название (Дом, Работа...)',
                  prefixIcon: Icon(Icons.label_outline)),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addrCtrl,
              decoration: const InputDecoration(
                  hintText: 'Полный адрес',
                  prefixIcon: Icon(Icons.location_on_outlined)),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  if (addrCtrl.text.trim().isEmpty) return;
                  try {
                    await service.addAddress(
                      label: labelCtrl.text,
                      address: addrCtrl.text,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('Не удалось сохранить адрес'),
                        backgroundColor: cRed,
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0),
                child: Text('Сохранить', style: manrope(15, FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
