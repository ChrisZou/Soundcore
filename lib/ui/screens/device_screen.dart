import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/recorder_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/scan_sheet.dart';
import '../widgets/widgets.dart';

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RecorderController>();
    if (!c.connected) {
      return _OfflineDeviceView(controller: c);
    }

    final info = c.info;
    final micBat = info?.battery;
    final caseBat = info?.boxBattery;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('设备'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: c.phase == AppPhase.busy ? null : c.refreshInfo,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '断开连接',
            onPressed: c.disconnect,
            icon: const Icon(Icons.link_off_rounded, color: AppColors.coral),
          ),
        ],
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            const ProductStage(),
            Center(
              child: Text(
                c.displayDeviceName,
                style: AppTypography.number.copyWith(
                  fontSize: 28,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              key: const ValueKey('device-battery-section'),
              children: [
                Expanded(
                  child: _BatteryCard(
                    label: '麦克风',
                    percent: micBat,
                    charging: info?.charging ?? false,
                    asset: 'assets/product/d3200_device_white.webp',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BatteryCard(
                    label: '充电盒',
                    percent: caseBat,
                    charging: info?.boxCharging ?? false,
                    asset: 'assets/product/d3200_chargebox_white.webp',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SectionLabel('录音'),
            _DeviceSection(
              key: const ValueKey('device-recording-section'),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AccentButton(
                          label: c.recording ? '录音中…' : '开始',
                          icon: Icons.mic_rounded,
                          color: AppColors.coral,
                          onPressed: c.recording || c.blocksRecordingControl
                              ? null
                              : c.startRecord,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AccentButton(
                          label: '暂停',
                          icon: Icons.pause_rounded,
                          filled: false,
                          color: AppColors.amber,
                          onPressed: !c.recording || c.phase == AppPhase.busy
                              ? null
                              : c.pauseRecord,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AccentButton(
                    label: '同步设备时钟',
                    icon: Icons.schedule_rounded,
                    filled: false,
                    onPressed: c.phase == AppPhase.busy ? null : c.syncTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('配对绑定'),
            _DeviceSection(
              key: const ValueKey('device-pairing-section'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AccentButton(
                          label: c.bound ? '已绑定' : '绑定',
                          icon: Icons.link_rounded,
                          onPressed: c.bound || c.phase == AppPhase.busy
                              ? null
                              : () => c.bindDevice(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AccentButton(
                          label: '解绑',
                          icon: Icons.link_off_rounded,
                          filled: false,
                          color: AppColors.textSecondary,
                          onPressed: !c.bound || c.phase == AppPhase.busy
                              ? null
                              : () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: AppColors.bgCard,
                                      title: const Text('确认解绑？'),
                                      content: const Text(
                                        '将向设备发送解绑指令（与飞书相同，payload 00）。\n'
                                        '• 不会清空录音或恢复出厂\n'
                                        '• 成功后会断开连接\n'
                                        '• 之后可再扫描、连接并重新绑定',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('解绑'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) await c.unbindDevice();
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('设备信息'),
            _DeviceSection(
              key: const ValueKey('device-info-section'),
              child: Column(
                children: [
                  const _DeviceInfoRow(label: '产品', value: 'D3200'),
                  const Divider(),
                  _DeviceInfoRow(
                    label: '序列号',
                    value: info?.serialNumber.isNotEmpty == true
                        ? info!.serialNumber
                        : '—',
                  ),
                  const Divider(),
                  _DeviceInfoRow(
                    label: '固件版本',
                    value: info?.firmwareVersion.isNotEmpty == true
                        ? info!.firmwareVersion
                        : '—',
                  ),
                  const Divider(),
                  _DeviceInfoRow(label: '存储', value: info?.storageLabel ?? '—'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('危险操作'),
            _DeviceSection(
              key: const ValueKey('device-danger-section'),
              borderColor: AppColors.coral.withValues(alpha: 0.25),
              child: AccentButton(
                label: '恢复出厂设置',
                icon: Icons.restart_alt_rounded,
                color: AppColors.coral,
                filled: false,
                onPressed: c.phase == AppPhase.busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.bgCard,
                            title: const Text('确定恢复出厂？'),
                            content: const Text(
                              '将发送重置指令（0x01/0xB8）。'
                              '设备将恢复默认设置。',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  '重置',
                                  style: TextStyle(color: AppColors.coral),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) await c.resetDevice();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    required this.label,
    required this.percent,
    required this.charging,
    required this.asset,
  });
  final String label;
  final int? percent;
  final bool charging;
  final String asset;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                percent == null ? '—' : '$percent%',
                style: AppTypography.number.copyWith(
                  fontSize: 35,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Image.asset(asset, width: 24, height: 24),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          charging ? '$label · 充电中' : label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: (percent ?? 0).clamp(0, 100) / 100,
          minHeight: 3,
          borderRadius: BorderRadius.circular(4),
          color: AppColors.accent,
          backgroundColor: AppColors.border,
        ),
      ],
    ),
  );
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection({
    super.key,
    required this.child,
    this.borderColor = AppColors.border,
  });

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: borderColor.withValues(alpha: .7)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Disconnected Device tab: still show last known / bound unit.
class _OfflineDeviceView extends StatelessWidget {
  const _OfflineDeviceView({required this.controller});

  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final d = c.displayDevice;

    return GradientScaffold(
      appBar: AppBar(title: const Text('设备')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            if (d != null) ...[
              SurfaceCard(
                glow: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProductStage(child: _OfflineProductImage()),
                    const SizedBox(height: 10),
                    Text(
                      d.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (c.bound || d.isBoundAdvertised) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: StatusPill(
                          label: c.bound ? '已绑定' : '广告已绑定',
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                    if (d.macAddress != null && d.macAddress!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        d.macAddress!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      '未连接',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AccentButton(
                      label: '扫描并连接',
                      icon: Icons.radar_rounded,
                      onPressed: () => showScanDevicesSheet(context),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 48),
              SurfaceCard(
                glow: true,
                child: Column(
                  children: [
                    const ProductStage(child: _OfflineProductImage()),
                    const SizedBox(height: 16),
                    Text(
                      'soundcore Work',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '未连接',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AccentButton(
                      label: '扫描设备',
                      icon: Icons.radar_rounded,
                      onPressed: () => showScanDevicesSheet(context),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfflineProductImage extends StatelessWidget {
  const _OfflineProductImage();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: '设备离线，蓝牙连接已断开',
      child: SizedBox(
        width: 220,
        height: 142,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.62,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0.2126,
                  0.7152,
                  0.0722,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: Image.asset(
                  'assets/product/d3200_device_connected_white.webp',
                  height: 132,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.headphones_rounded,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 7,
              right: 27,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.coral.withValues(alpha: 0.24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.coral.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bluetooth_disabled_rounded,
                  size: 24,
                  color: AppColors.coral,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
