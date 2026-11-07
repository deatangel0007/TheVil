import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => _controller.text = t);
  }

  Future<void> _add() async {
    final app = context.read<AppState>();
    try {
      final n = await app.addSubscription(_controller.text);
      _controller.clear();
      _toast('اشتراک اضافه شد: $n سرور');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _refresh(String id) async {
    final app = context.read<AppState>();
    try {
      final n = await app.refreshSubscription(id);
      _toast('به‌روز شد: $n سرور');
    } catch (e) {
      _toast('$e');
    }
  }

  String _ago(int? ms) {
    if (ms == null) return 'هنوز به‌روز نشده';
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'همین الان';
    if (d.inHours < 1) return '${d.inMinutes} دقیقه پیش';
    if (d.inDays < 1) return '${d.inHours} ساعت پیش';
    return '${d.inDays} روز پیش';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('اشتراک‌ها')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://example.com/sub/...',
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  tooltip: 'چسباندن',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _paste,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: app.busy ? null : _add,
            icon: app.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_link_rounded),
            label: Text(app.busy ? 'در حال دانلود...' : 'افزودن اشتراک'),
          ),
          const SizedBox(height: 20),
          if (app.subs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Text(
                'هنوز اشتراکی اضافه نکرده‌اید.\nلینک اشتراک را بچسبانید و «افزودن» را بزنید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, height: 1.8),
              ),
            ),
          for (final s in app.subs)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.rss_feed_rounded, color: AppColors.red),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${app.servers.where((e) => e.subId == s.id).length} سرور • ${_ago(s.updatedMs)}',
                  style: const TextStyle(color: AppColors.textDim),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'به‌روزرسانی',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: app.busy ? null : () => _refresh(s.id),
                    ),
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => app.removeSubscription(s.id),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
