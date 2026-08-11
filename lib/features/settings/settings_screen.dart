// lib/features/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/providers/theme_controller.dart';
import '../../core/services/n8n_service.dart';
import '../../core/services/wifi_attendance_service.dart';
import '../../core/services/apk_update_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/theme/app_theme.dart';
import '../super_admin/reset_app_dialog.dart';
import '../super_admin/archive_completed_tasks_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifs = true;
  bool _emailDigest = false;
  bool _biometricEnabled = false;

  // n8n integration
  final _webhookCtrl = TextEditingController();
  bool _savingWebhook = false;
  bool _testingWebhook = false;
  String? _webhookStatus;

  // WiFi attendance
  final _wifiSsidCtrl = TextEditingController();
  bool _wifiEnabled = false;
  bool _savingWifi = false;
  String? _wifiStatus;

  @override
  void initState() {
    super.initState();
    N8nService.getWebhookUrl().then((url) {
      if (mounted) _webhookCtrl.text = url;
    });
    WifiAttendanceService.getCompanySsid().then((ssid) {
      if (mounted && ssid != null) setState(() => _wifiSsidCtrl.text = ssid);
    });
    WifiAttendanceService.isEnabled().then((v) {
      if (mounted) setState(() => _wifiEnabled = v);
    });
    _loadBiometricStatus();
  }

  Future<void> _loadBiometricStatus() async {
    final userId = context.read<AuthNotifier>().profile?.id;
    if (userId != null) {
      final enabled =
          await BiometricService.instance.isBiometricEnabled(userId);
      if (mounted) setState(() => _biometricEnabled = enabled);
    }
  }

  Future<void> _toggleBiometrics(bool enable) async {
    final userId = context.read<AuthNotifier>().profile?.id;
    if (userId == null) return;

    if (!enable) {
      await BiometricService.instance.setBiometricEnabled(userId, false);
      if (mounted) {
        setState(() => _biometricEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('biometrics_disabled_msg'))),
        );
      }
      return;
    }

    final isAvailable = await BiometricService.instance.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('biometrics_not_enrolled'))),
        );
      }
      return;
    }

    final success = await BiometricService.instance.authenticate(
      localizedReason: S.t('biometric_enable_reason'),
    );

    if (success) {
      await BiometricService.instance.setBiometricEnabled(userId, true);
      if (mounted) {
        setState(() => _biometricEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('biometrics_enabled_success'))),
        );
      }
    } else {
      if (mounted) {
        setState(() => _biometricEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('biometrics_auth_failed'))),
        );
      }
    }
  }

  @override
  void dispose() {
    _webhookCtrl.dispose();
    _wifiSsidCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveWebhook() async {
    setState(() {
      _savingWebhook = true;
      _webhookStatus = null;
    });
    await N8nService.saveWebhookUrl(_webhookCtrl.text.trim());
    if (mounted) {
      setState(() {
        _savingWebhook = false;
        _webhookStatus = 'Saved';
      });
    }
  }

  Future<void> _testWebhook() async {
    final url = _webhookCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _webhookStatus = 'Enter a URL first');
      return;
    }
    setState(() {
      _testingWebhook = true;
      _webhookStatus = null;
    });
    await N8nService.notifyTaskUpdate(
      clientPhone: '+0000000000',
      clientName: 'Test Client',
      taskTitle: 'Test Task',
      newStatus: 'in_progress',
      priority: 'medium',
      completionPercentage: 50,
      updatedBy: 'Admin (test)',
    );
    if (mounted) {
      setState(() {
        _testingWebhook = false;
        _webhookStatus = 'Test sent — check n8n';
      });
    }
  }

  Future<void> _saveWifiSettings() async {
    setState(() {
      _savingWifi = true;
      _wifiStatus = null;
    });
    final adminId = context.read<AuthNotifier>().profile?.id;
    try {
      await WifiAttendanceService.setCompanySsid(
        _wifiSsidCtrl.text.trim(),
        updatedBy: adminId,
      );
      await WifiAttendanceService.setEnabled(_wifiEnabled, updatedBy: adminId);
      if (mounted) {
        setState(() {
          _savingWifi = false;
          _wifiStatus = 'Saved';
        });
      }
      // Re-run detection immediately so the change takes effect now.
      WifiAttendanceService.instance.checkNow();
    } catch (e) {
      if (mounted) {
        setState(() {
          _savingWifi = false;
          _wifiStatus = 'Could not save — check your connection';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final isManager = profile?.isAdminOrManager == true;
    final isAdmin = profile?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(S.t('settings'))),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  TAvatar(name: profile?.fullName ?? '', size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.fullName ?? '',
                          style: AppTextStyles.headlineSm.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                        Text(
                          profile?.role ?? '',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onPrimary.withValues(alpha: 0.7),
                          ),
                        ),
                        Text(
                          S.isArabic
                              ? S.t('arabic_interface')
                              : S.t('english_interface'),
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onPrimary.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Update Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update_outlined,
                    color: AppColors.gold,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.t('check_updates'),
                          style: AppTextStyles.labelMd,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          S.t('check_updates_sub'),
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: const Color(0xFF000000),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => ApkUpdateService.checkForUpdates(
                      context,
                      isManual: true,
                      forceDialog: true,
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(S.t('update')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Team section — admin / manager only
            if (isManager) ...[
              _SectionTitle(title: S.t('team')),
              _SettingsTile(
                icon: Icons.people_outline,
                title: S.t('user_management'),
                onTap: () => context.push('/users'),
              ),
              // Roles & Privileges — admins manage everyone & change roles;
              // managers manage privileges for their own team.
              _SettingsTile(
                icon: Icons.manage_accounts_outlined,
                title: isAdmin ? S.t('roles_privileges') : S.t('team_privileges'),
                onTap: () => context.push('/roles'),
              ),
              _SettingsTile(
                icon: Icons.warning_amber_outlined,
                title: S.t('penalty_management'),
                onTap: () => context.push('/penalties'),
              ),
              const Divider(height: 1),
            ] else if (profile?.isClient != true) ...[
              _SettingsTile(
                icon: Icons.warning_amber_outlined,
                title: S.t('my_penalties'),
                onTap: () => context.push('/penalties'),
              ),
              const Divider(height: 1),
            ],

            // ── Attendance Settings (all roles that get tracked) ─────────────
            if (profile?.isClient != true) ...[
              _SectionTitle(title: S.t('attendance')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wifi, color: AppColors.gold, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          S.t('wifi_attendance'),
                          style: AppTextStyles.bodyMd,
                        ),
                        const Spacer(),
                        // Toggle is interactive for admins only; others see status.
                        Switch(
                          value: _wifiEnabled,
                          onChanged: isAdmin
                              ? (v) async {
                                  setState(() => _wifiEnabled = v);
                                  final adminId = context.read<AuthNotifier>().profile?.id;
                                  await WifiAttendanceService.setEnabled(v, updatedBy: adminId);
                                }
                              : null,
                          activeThumbColor: AppColors.gold,
                          activeTrackColor: AppColors.primary,
                        ),
                      ],
                    ),
                    Text(
                      isAdmin
                          ? S.t('wifi_attendance_admin_desc')
                          : S.t('wifi_attendance_user_desc'),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Admin: editable SSID field. Others: read-only display.
                    if (isAdmin)
                      TextField(
                        controller: _wifiSsidCtrl,
                        enabled: _wifiEnabled,
                        decoration: InputDecoration(
                          labelText: S.t('wifi_ssid_label'),
                          hintText: S.t('wifi_ssid_hint'),
                          hintStyle: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          prefixIcon: const Icon(
                            Icons.wifi_outlined,
                            color: AppColors.gold,
                            size: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.outlineVariant,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.outlineVariant.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.wifi_outlined,
                              color: AppColors.gold,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    S.t('wifi_ssid_label'),
                                    style: AppTextStyles.labelCaps.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _wifiSsidCtrl.text.isEmpty
                                        ? S.t('wifi_not_set')
                                        : _wifiSsidCtrl.text,
                                    style: AppTextStyles.bodyMd.copyWith(
                                      color: _wifiSsidCtrl.text.isEmpty
                                          ? AppColors.onSurfaceVariant
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),

                    // Save button — admin only.
                    if (isAdmin) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _savingWifi ? null : _saveWifiSettings,
                          icon: _savingWifi
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : Icon(
                                  Icons.save_outlined,
                                  size: 16,
                                  color: AppColors.onPrimary,
                                ),
                          label: Text(S.t('save_attendance_settings')),
                        ),
                      ),
                    ],
                    if (isAdmin && _wifiStatus != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _wifiStatus == 'Saved'
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 14,
                            color: _wifiStatus == 'Saved'
                                ? AppColors.statusDone
                                : AppColors.gold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _wifiStatus!,
                            style: AppTextStyles.bodySm.copyWith(
                              color: _wifiStatus == 'Saved'
                                  ? AppColors.statusDone
                                  : AppColors.gold,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.gold.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 14,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Android requirements',
                                style: AppTextStyles.labelMd.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• Allow Location permission when prompted (required by Android to read WiFi name)\n'
                            '• On Android 10+, grant "Allow all the time" for background detection\n'
                            '• iPhone users: WiFi SSID access requires iOS Location permission',
                            style: AppTextStyles.bodySm.copyWith(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],

            // Super Admin Control Panel — Exclusive for Super Admin (ammar@cashback.com)
            if (profile?.isSuperAdmin == true) ...[
              _SectionTitle(title: S.t('super_admin_controls')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.stars, color: AppColors.gold, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            S.t('super_admin_panel'),
                            style: AppTextStyles.labelMd.copyWith(color: AppColors.gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        S.t('super_admin_panel_desc'),
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('Create New Admin / User'),
                            onPressed: () => context.push('/create-user'),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.analytics_outlined, size: 18),
                            label: const Text('Generate Master Detailed Report'),
                            onPressed: () => context.push('/super-admin/report'),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.archive_outlined, size: 18),
                            label: const Text('Batch Archive Tasks'),
                            onPressed: () async {
                              await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const ArchiveCompletedTasksDialog(),
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.inventory_2_outlined, size: 18),
                            label: const Text('Archived Tasks Manager'),
                            onPressed: () => context.push('/super-admin/archived-tasks'),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.delete_forever_outlined, size: 18),
                            label: const Text('Reset Application Data'),
                            onPressed: () async {
                              await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const ResetAppDialog(),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],

            // n8n Telegram integration — admin only
            if (profile?.isAdmin == true) ...[
              _SectionTitle(title: S.t('integrations')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.webhook,
                          color: AppColors.gold,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(S.t('n8n_webhook_title'), style: AppTextStyles.bodyMd),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      S.t('n8n_webhook_desc'),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _webhookCtrl,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        hintText: 'https://your-n8n-server/webhook/...',
                        hintStyle: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                        prefixIcon: const Icon(
                          Icons.link,
                          color: AppColors.gold,
                          size: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _testingWebhook ? null : _testWebhook,
                            icon: _testingWebhook
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  )
                                : Icon(
                                    Icons.send_outlined,
                                    size: 16,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                            label: Text(
                              S.t('test'),
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _savingWebhook ? null : _saveWebhook,
                            icon: _savingWebhook
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    Icons.save_outlined,
                                    size: 16,
                                    color: AppColors.onPrimary,
                                  ),
                            label: Text(S.t('save_url')),
                          ),
                        ),
                      ],
                    ),
                    if (_webhookStatus != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _webhookStatus == 'Saved'
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 14,
                            color: _webhookStatus == 'Saved'
                                ? AppColors.statusDone
                                : AppColors.gold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _webhookStatus!,
                            style: AppTextStyles.bodySm.copyWith(
                              color: _webhookStatus == 'Saved'
                                  ? AppColors.statusDone
                                  : AppColors.gold,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],

            // Security
            _SectionTitle(title: S.t('security')),
            SwitchListTile(
              value: _biometricEnabled,
              onChanged: (v) => _toggleBiometrics(v),
              title: Text(
                S.t('enable_biometric_login'),
                style: AppTextStyles.bodyMd,
              ),
              subtitle: Text(
                S.t('enable_biometric_login_sub'),
                style: AppTextStyles.bodySm,
              ),
              secondary: const Icon(
                Icons.fingerprint_outlined,
                color: AppColors.gold,
              ),
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.primary,
            ),
            const Divider(height: 1),

            // Preferences
            _SectionTitle(title: S.t('preferences')),
            SwitchListTile(
              value: _pushNotifs,
              onChanged: (v) async {
                setState(() => _pushNotifs = v);
                if (v) {
                  await PushNotificationService.instance
                      .requestNotificationPermission();
                }
              },
              title: Text(S.t('push_notifs'), style: AppTextStyles.bodyMd),
              subtitle: Text(
                S.t('push_notifs_sub'),
                style: AppTextStyles.bodySm,
              ),
              secondary: const Icon(
                Icons.notifications_outlined,
                color: AppColors.gold,
              ),
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.primary,
            ),
            SwitchListTile(
              value: _emailDigest,
              onChanged: (v) => setState(() => _emailDigest = v),
              title: Text(S.t('email_digest'), style: AppTextStyles.bodyMd),
              subtitle: Text(
                S.t('email_digest_sub'),
                style: AppTextStyles.bodySm,
              ),
              secondary: const Icon(
                Icons.email_outlined,
                color: AppColors.gold,
              ),
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.primary,
            ),
            SwitchListTile(
              value: context.watch<ThemeController>().isDark,
              onChanged: (v) => context.read<ThemeController>().setDark(v),
              title: Text(S.t('dark_mode'), style: AppTextStyles.bodyMd),
              subtitle: Text(
                S.t('dark_mode_sub'),
                style: AppTextStyles.bodySm,
              ),
              secondary: const Icon(
                Icons.dark_mode_outlined,
                color: AppColors.gold,
              ),
              activeThumbColor: AppColors.gold,
              activeTrackColor: AppColors.primary,
            ),
            ListTile(
              leading: const Icon(Icons.language, color: AppColors.gold),
              title: Text(S.t('language'), style: AppTextStyles.bodyMd),
              subtitle: Text(
                context.watch<LocaleController>().isArabic
                    ? S.t('arabic')
                    : S.t('english'),
                style: AppTextStyles.bodySm,
              ),
              trailing: Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceVariant,
              ),
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.surfaceContainerLowest,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (_) => SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(S.t('select_language'), style: AppTextStyles.headlineSm),
                        const Divider(),
                        ...[('en', S.t('english')), ('ar', S.t('arabic'))].map(
                          (l) => ListTile(
                            title: Text(l.$2, style: AppTextStyles.bodyMd),
                            trailing:
                                context
                                        .read<LocaleController>()
                                        .locale
                                        .languageCode ==
                                    l.$1
                                ? const Icon(Icons.check, color: AppColors.gold)
                                : null,
                            onTap: () {
                              final userId = context.read<AuthNotifier>().profile?.id;
                              context.read<LocaleController>().setLanguage(l.$1, userId: userId);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),

            // About & Updates
            _SectionTitle(title: S.t('about_updates')),
            _SettingsTile(
              icon: Icons.system_update_outlined,
              title: S.t('check_updates'),
              subtitle: 'v1.6.1+7',
              onTap: () => ApkUpdateService.checkForUpdates(
                context,
                isManual: true,
              ),
            ),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: S.t('privacy_policy'),
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: S.t('terms_service'),
              onTap: () {},
            ),
            const Divider(height: 1),

            // Sign out
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await context.read<AuthNotifier>().signOut();
                  },
                  icon: const Icon(Icons.logout, color: AppColors.statusHigh),
                  label: Text(
                    S.t('sign_out'),
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.statusHigh,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.statusHigh),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(title, style: AppTextStyles.labelCaps),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.gold),
    title: Text(title, style: AppTextStyles.bodyMd),
    subtitle: subtitle != null
        ? Text(subtitle!, style: AppTextStyles.bodySm)
        : null,
    trailing: onTap != null
        ? Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant)
        : null,
    onTap: onTap,
  );
}
