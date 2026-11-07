import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/server_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'subscriptions_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  void _toast(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
      );
  }

  Future<void> _add(BuildContext context, String text) async {
    final app = context.read<AppState>();
    try {
      final msg = await app.addFromAny(text);
      _toast(context, msg);
    } catch (e) {
      _toast(context, '$e');
    }
  }

  Future<void> _paste(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    await _add(context, data?.text ?? '');
  }

  Future<void> _scan(BuildContext context) async {
    final app = context.read<AppState>();
    try {
      final text = await app.scanQr();
      if (text == null || text.isEmpty) return; // لغو شد
      if (!context.mounted) return;
      await _add(context, text);
    } catch (e) {
      _toast(context, '$e');
    }
  }

  Color _pingColor(int? ms) {
    if (ms == null) return AppColors.textDim;
    if (ms < 0) return AppColors.red;
    if (ms < 300) return AppColors.green;
    return Colors.orangeAccent;
  }

  String _pingText(int? ms) {
    if (ms == null) return '—';
    if (ms < 0) return 'ناموفق';
    return '$ms ms';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('سرورها'),
        bottom: app.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                    minHeight: 3, color: AppColors.red),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'اسکن QR',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => _scan(context),
          ),
          IconButton(
            tooltip: 'اشتراک‌ها',
            icon: const Icon(Icons.rss_feed_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'تست پینگ',
            icon: const Icon(Icons.speed_rounded),
            onPressed: app.servers.isEmpty ? null : app.pingAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _paste(context),
        icon: const Icon(Icons.content_paste_rounded),
        label: const Text('افزودن از کلیپ‌بورد'),
      ),
      body: app.servers.isEmpty
          ? const Center(
              child: Text(
                'هنوز کانفیگی اضافه نکرده‌اید.\nلینک کانفیگ یا لینک اشتراک (sub) را کپی کنید و دکمه‌ی پایین را بزنید،\nیا با آیکن QR بالا اسکن کنید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, height: 1.8),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: app.servers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = app.servers[i];
                final isSel = s.id == app.selected?.id;
                return Dismissible(
                  key: ValueKey(s.id),
                  background: Container(
                    decoration: BoxDecoration(
                      color: AppColors.redDark,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete_rounded),
                  ),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => app.remove(s.id),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isSel ? AppColors.red : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => app.select(s.id),
                      leading: Icon(
                        isSel
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSel ? AppColors.red : AppColors.textDim,
                      ),
                      title: Text(s.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${s.protocolLabel} • ${s.address}:${s.port}',
                        style: const TextStyle(color: AppColors.textDim),
                      ),
                      trailing: Text(
                        _pingText(s.pingMs),
                        style: TextStyle(color: _pingColor(s.pingMs)),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
