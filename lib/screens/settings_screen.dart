import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'apps_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _custom = TextEditingController();
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final dns = context.read<AppState>().settings.remoteDns;
    if (!dnsPresets.any((p) => p.ip == dns)) _custom.text = dns;
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _setDns(String ip) async {
    final app = context.read<AppState>();
    await app.updateSettings(app.settings.copyWith(remoteDns: ip));
    if (mounted) setState(() => _changed = true);
  }

  Future<void> _applyCustom() async {
    final v = _custom.text.trim();
    if (!AppSettings.isValidIpv4(v)) {
      _toast('آدرس DNS معتبر نیست (مثال: 1.1.1.1)');
      return;
    }
    await _setDns(v);
    _toast('DNS ذخیره شد');
  }

  Future<void> _setMode(PerAppMode m) async {
    final app = context.read<AppState>();
    await app.updateSettings(app.settings.copyWith(perAppMode: m));
    if (mounted) setState(() => _changed = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.settings;
    final isPreset = dnsPresets.any((p) => p.ip == st.remoteDns);
    final connected = app.status == ConnStatus.connected;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Text('تنظیمات',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          if (connected && _changed)
            Card(
              color: AppColors.redDark.withOpacity(0.3),
              child: ListTile(
                leading: const Icon(Icons.info_outline, color: AppColors.red),
                title: const Text('تغییرات با اتصال بعدی اعمال می‌شود'),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: () {
                    setState(() => _changed = false);
                    app.reconnect();
                  },
                  child: const Text('اتصال مجدد'),
                ),
              ),
            ),
          const _SectionTitle('DNS'),
          Card(
            child: Column(
              children: [
                for (final p in dnsPresets)
                  ListTile(
                    onTap: () => _setDns(p.ip),
                    leading: Icon(
                      st.remoteDns == p.ip
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: st.remoteDns == p.ip
                          ? AppColors.red
                          : AppColors.textDim,
                    ),
                    title: Text(p.label),
                    trailing: Text(p.ip,
                        style: const TextStyle(color: AppColors.textDim)),
                  ),
                ListTile(
                  leading: Icon(
                    !isPreset
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: !isPreset ? AppColors.red : AppColors.textDim,
                  ),
                  title: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _custom,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'دلخواه، مثلاً 10.202.10.10',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _applyCustom(),
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _applyCustom,
                    child: const Text('ذخیره'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Text(
              'DNS از داخل تونل VPN پرسیده می‌شود.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          const _SectionTitle('پروکسی بر اساس برنامه'),
          Card(
            child: Column(
              children: [
                _modeTile(st, PerAppMode.off, 'همه‌ی برنامه‌ها',
                    'تمام ترافیک گوشی از VPN رد می‌شود'),
                _modeTile(st, PerAppMode.only, 'فقط برنامه‌های انتخابی',
                    'فقط برنامه‌هایی که انتخاب می‌کنی از VPN رد می‌شوند'),
                _modeTile(st, PerAppMode.bypass, 'همه به‌جز برنامه‌های انتخابی',
                    'برنامه‌های انتخابی مستقیم (بدون VPN) می‌روند'),
                if (st.perAppMode != PerAppMode.off) ...[
                  const Divider(height: 1),
                  ListTile(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AppsScreen()),
                      );
                      if (mounted) setState(() => _changed = true);
                    },
                    leading: const Icon(Icons.apps_rounded, color: AppColors.red),
                    title: const Text('انتخاب برنامه‌ها'),
                    subtitle: Text(
                      st.perAppPackages.isEmpty
                          ? 'هنوز برنامه‌ای انتخاب نشده'
                          : '${st.perAppPackages.length} برنامه انتخاب شده',
                      style: const TextStyle(color: AppColors.textDim),
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                  ),
                  if (st.perAppPackages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'تا برنامه‌ای انتخاب نکنی، حالت «همه‌ی برنامه‌ها» اجرا می‌شود.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _modeTile(AppSettings st, PerAppMode m, String title, String sub) {
    final sel = st.perAppMode == m;
    return ListTile(
      onTap: () => _setMode(m),
      leading: Icon(
        sel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: sel ? AppColors.red : AppColors.textDim,
      ),
      title: Text(title),
      subtitle: Text(sub,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.red,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      );
}
