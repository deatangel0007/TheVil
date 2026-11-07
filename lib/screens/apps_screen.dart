import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<Map<String, dynamic>>? _apps;
  String _query = '';
  bool _showSystem = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<AppState>().listApps();
    list.sort((a, b) => (a['label'] as String)
        .toLowerCase()
        .compareTo((b['label'] as String).toLowerCase()));
    if (mounted) setState(() => _apps = list);
  }

  Future<void> _toggle(String pkg, bool on) async {
    final app = context.read<AppState>();
    final set = {...app.settings.perAppPackages};
    on ? set.add(pkg) : set.remove(pkg);
    await app.updateSettings(app.settings.copyWith(perAppPackages: set));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final selected = app.settings.perAppPackages;
    final q = _query.trim().toLowerCase();

    final apps = _apps;
    final shown = apps == null
        ? const <Map<String, dynamic>>[]
        : apps.where((a) {
            final pkg = a['package'] as String;
            final label = (a['label'] as String).toLowerCase();
            if (!_showSystem && a['system'] == true && !selected.contains(pkg)) {
              return false;
            }
            return q.isEmpty || label.contains(q) || pkg.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('انتخاب برنامه‌ها (${selected.length})'),
        actions: [
          IconButton(
            tooltip: _showSystem ? 'پنهان کردن برنامه‌های سیستمی' : 'نمایش برنامه‌های سیستمی',
            icon: Icon(_showSystem
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _showSystem = !_showSystem),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'جستجو',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: apps == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.red))
                : apps.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'فهرست برنامه‌ها خوانده نشد.\n(در حالت شبیه‌سازی یا نبود مجوز)',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textDim, height: 1.8),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final a = shown[i];
                          final pkg = a['package'] as String;
                          return CheckboxListTile(
                            value: selected.contains(pkg),
                            activeColor: AppColors.red,
                            onChanged: (v) => _toggle(pkg, v ?? false),
                            title: Text(a['label'] as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  pkg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textDim, fontSize: 11),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
