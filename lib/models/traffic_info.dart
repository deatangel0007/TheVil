class TrafficInfo {
  final int downBps;
  final int upBps;
  final int downTotal;
  final int upTotal;

  const TrafficInfo({
    this.downBps = 0,
    this.upBps = 0,
    this.downTotal = 0,
    this.upTotal = 0,
  });

  static const zero = TrafficInfo();

  static String formatBytes(int b) {
    if (b < 1024) return '$b B';
    final kb = b / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(int bps) => '${formatBytes(bps)}/s';
}
