import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/traffic_info.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/connect_button.dart';
import 'logs_screen.dart';

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
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: 'لاگ‌ها',
                icon: const Icon(Icons.bug_report_outlined,
                    color: AppColors.textDim),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                ),
              ),
            ),
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
                ]),
                Column(children: [
            const SizedBox(height: 24),
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
            if (app.testResult != null && app.status == ConnStatus.connected)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  app.testResult!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: app.testResult!.contains('✓')
                        ? AppColors.green
                        : (app.testResult!.contains('✗')
                            ? AppColors.red
                            : AppColors.textDim),
                  ),
                ),
              ),
            if (app.status == ConnStatus.connected && app.trafficSupported)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ValueListenableBuilder<TrafficInfo>(
                  valueListenable: app.traffic,
                  builder: (_, t, __) => _TrafficRow(info: t),
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
            if (app.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.redDark.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('خطا (متن را کپی کن و بفرست)',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: app.clearError,
                          ),
                        ],
                      ),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: SelectableText(
                          app.error!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
                ]),
                Column(children: [
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
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  final TrafficInfo info;
  const _TrafficRow({required this.info});

  Widget _cell(IconData icon, Color color, String speed, String total) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(speed,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: color, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(total,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _cell(Icons.arrow_downward_rounded, AppColors.green,
              TrafficInfo.formatSpeed(info.downBps),
              TrafficInfo.formatBytes(info.downTotal)),
          Container(width: 1, height: 30, color: AppColors.textDim.withOpacity(0.3)),
          _cell(Icons.arrow_upward_rounded, AppColors.red,
              TrafficInfo.formatSpeed(info.upBps),
              TrafficInfo.formatBytes(info.upTotal)),
        ],
      ),
    );
  }
}
