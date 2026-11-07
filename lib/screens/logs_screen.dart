import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _text = '...';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await context.read<AppState>().fetchLogs();
    if (mounted) setState(() => _text = t.isEmpty ? '(لاگی ثبت نشده)' : t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لاگ‌ها'),
        actions: [
          IconButton(
            tooltip: 'به‌روزرسانی',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'کپی',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _text));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('کپی شد')));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(
            _text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              fontFamily: 'monospace',
              color: AppColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
