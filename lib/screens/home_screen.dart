import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/connect_button.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenServers;
  const HomeScreen({super.key, required this.onOpenServers});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final server = app.selected;

    final (label, color) = switch (app.status) {
      ConnStatus.connected => ('متصل شد', AppColors.green),
      ConnStatus.connecting => ('در حال اتصال...', AppColors.textDim),
      ConnStatus.disconnected => ('قطع است', AppColors.textDim),
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Image.asset('assets/logo_mark.png', height: 56),
            const SizedBox(height: 6),
            const Text(
              'TheVil',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                color: AppColors.red,
              ),
            ),
            const Spacer(),
            ConnectButton(
              status: app.status,
              onTap: server == null ? onOpenServers : app.toggle,
            ),
            const SizedBox(height: 28),
            Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            if (app.mockMode && app.status == ConnStatus.connected)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'حالت شبیه‌سازی: هسته‌ی نیتیو هنوز وصل نشده',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ),
            const Spacer(),
            Card(
              child: ListTile(
                onTap: onOpenServers,
                leading: const Icon(Icons.dns_rounded, color: AppColors.red),
                title: Text(server?.name ?? 'سروری انتخاب نشده'),
                subtitle: Text(
                  server == null
                      ? 'برای افزودن کانفیگ ضربه بزنید'
                      : '${server.protocolLabel} • ${server.address}:${server.port}',
                  style: const TextStyle(color: AppColors.textDim),
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
