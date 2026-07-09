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
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifs  = true;
  bool _emailDigest = false;

  // n8n integration
  final _webhookCtrl = TextEditingController();
  bool _savingWebhook  = false;
  bool _testingWebhook = false;
  String? _webhookStatus;

  // WiFi attendance
  final _wifiSsidCtrl = TextEditingController();
  bool _wifiEnabled     = false;
  bool _savingWifi      = false;
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
  }

  @override
  void dispose() {
    _webhookCtrl.dispose();
    _wifiSsidCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveWebhook() async {
    setState(() { _savingWebhook = true; _webhookStatus = null; });
    await N8nService.saveWebhookUrl(_webhookCtrl.text.trim());
    if (mounted) setState(() { _savingWebhook = false; _webhookStatus = 'Saved'; });
  }

  Future<void> _testWebhook() async {
    final url = _webhookCtrl.text.trim();
    if (url.isEmpty) { setState(() => _webhookStatus = 'Enter a URL first'); return; }
    setState(() { _testingWebhook = true; _webhookStatus = null; });
    await N8nService.notifyTaskUpdate(
      clientPhone:          '+0000000000',
      clientName:           'Test Client',
      taskTitle:            'Test Task',
      newStatus:            'in_progress',
      priority:             'medium',
      completionPercentage: 50,
      updatedBy:            'Admin (test)',
    );
    if (mounted) setState(() { _testingWebhook = false; _webhookStatus = 'Test sent — check n8n'; });
  }

  Future<void> _saveWifiSettings() async {
    setState(() { _savingWifi = true; _wifiStatus = null; });
    final adminId = context.read<AuthNotifier>().profile?.id;
    try {
      await WifiAttendanceService.setCompanySsid(
        _wifiSsidCtrl.text.trim(), updatedBy: adminId);
      await WifiAttendanceService.setEnabled(_wifiEnabled, updatedBy: adminId);
      if (mounted) setState(() { _savingWifi = false; _wifiStatus = 'Saved'; });
      // Re-run detection immediately so the change takes effect now.
      WifiAttendanceService.instance.checkNow();
    } catch (e) {
      if (mounted) setState(() {
        _savingWifi = false;
        _wifiStatus = 'Could not save — check your connection';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile   = context.watch<AuthNotifier>().profile;
    final isManager = profile?.isAdminOrManager == true;
    final isAdmin   = profile?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Profile card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              TAvatar(name: profile?.fullName ?? '', size: 56),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile?.fullName ?? '',
                  style: AppTextStyles.headlineSm.copyWith(color: Colors.white)),
                Text(profile?.role ?? '',
                  style: AppTextStyles.bodySm.copyWith(color: Colors.white54)),
                Text(
                  profile?.preferredLanguage == 'ar' ? 'Arabic interface' : 'English interface',
                  style: AppTextStyles.bodySm.copyWith(color: Colors.white38),
                ),
              ])),
            ]),
          ),

          // Team section — admin / manager only
          if (isManager) ...[
            const _SectionTitle(title: 'TEAM'),
            _SettingsTile(
              icon: Icons.people_outline, title: 'User Management',
              onTap: () => context.push('/users'),
            ),
            // Roles & Privileges — admins manage everyone & change roles;
            // managers manage privileges for their own team.
            _SettingsTile(
              icon: Icons.manage_accounts_outlined,
              title: isAdmin ? 'Roles & Privileges' : 'Team Privileges',
              onTap: () => context.push('/roles'),
            ),
            _SettingsTile(
              icon: Icons.warning_amber_outlined, title: 'Penalty Management',
              onTap: () => context.push('/penalties'),
            ),
            const Divider(height: 1),
          ],

          // ── Attendance Settings (all roles that get tracked) ─────────────
          if (profile?.isClient != true) ...[
            const _SectionTitle(title: 'ATTENDANCE'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.wifi, color: AppColors.gold, size: 20),
                  const SizedBox(width: 10),
                  Text('WiFi Auto-Attendance', style: AppTextStyles.bodyMd),
                  const Spacer(),
                  // Toggle is interactive for admins only; others see status.
                  Switch(
                    value: _wifiEnabled,
                    onChanged: isAdmin
                        ? (v) => setState(() => _wifiEnabled = v)
                        : null,
                    activeColor: AppColors.gold,
                    activeTrackColor: AppColors.primary,
                  ),
                ]),
                Text(
                  isAdmin
                      ? 'When enabled, employees and managers are automatically '
                        'checked in when their device connects to the company '
                        'WiFi and checked out when they disconnect.'
                      : 'When you connect to the company WiFi, your attendance '
                        'is recorded automatically and sent for approval. '
                        'These settings are managed by your administrator.',
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                // Admin: editable SSID field. Others: read-only display.
                if (isAdmin)
                  TextField(
                    controller: _wifiSsidCtrl,
                    enabled: _wifiEnabled,
                    decoration: InputDecoration(
                      labelText: 'Company WiFi Name (SSID)',
                      hintText: 'e.g. CompanyOffice_5G',
                      hintStyle: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      prefixIcon: const Icon(Icons.wifi_outlined, color: AppColors.gold, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.outlineVariant)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.outlineVariant)),
                      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.4))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Row(children: [
                      const Icon(Icons.wifi_outlined, color: AppColors.gold, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Company WiFi Name (SSID)',
                            style: AppTextStyles.labelCaps.copyWith(
                              color: AppColors.onSurfaceVariant, fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(
                            _wifiSsidCtrl.text.isEmpty
                                ? 'Not set by administrator yet'
                                : _wifiSsidCtrl.text,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: _wifiSsidCtrl.text.isEmpty
                                  ? AppColors.onSurfaceVariant
                                  : AppColors.onSurface),
                          ),
                        ],
                      )),
                      Icon(Icons.lock_outline, size: 16, color: AppColors.onSurfaceVariant),
                    ]),
                  ),

                // Save button — admin only.
                if (isAdmin) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _savingWifi ? null : _saveWifiSettings,
                      icon: _savingWifi
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 16, color: Colors.white),
                      label: const Text('Save Attendance Settings'),
                    ),
                  ),
                ],
                if (isAdmin && _wifiStatus != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(
                      _wifiStatus == 'Saved' ? Icons.check_circle_outline : Icons.info_outline,
                      size: 14,
                      color: _wifiStatus == 'Saved' ? AppColors.statusDone : AppColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Text(_wifiStatus!,
                      style: AppTextStyles.bodySm.copyWith(
                        color: _wifiStatus == 'Saved' ? AppColors.statusDone : AppColors.gold)),
                  ]),
                ],
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.info_outline, size: 14, color: AppColors.gold),
                      const SizedBox(width: 6),
                      Text('Android requirements', style: AppTextStyles.labelMd.copyWith(fontSize: 12)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      '• Allow Location permission when prompted (required by Android to read WiFi name)\n'
                      '• On Android 10+, grant "Allow all the time" for background detection\n'
                      '• iPhone users: WiFi SSID access requires iOS Location permission',
                      style: AppTextStyles.bodySm.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ]),
            ),
            const Divider(height: 1),
          ],

          // n8n Telegram integration — admin only
          if (profile?.isAdmin == true) ...[
            const _SectionTitle(title: 'INTEGRATIONS'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.webhook, color: AppColors.gold, size: 20),
                  const SizedBox(width: 10),
                  Text('n8n Webhook URL', style: AppTextStyles.bodyMd),
                ]),
                const SizedBox(height: 4),
                Text(
                  'When a task is updated the app will POST to this URL '
                  'with the client\'s phone number so n8n can send a Telegram notification.',
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _webhookCtrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://your-n8n-server/webhook/...',
                    hintStyle: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    prefixIcon: const Icon(Icons.link, color: AppColors.gold, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.outlineVariant)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.outlineVariant)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testingWebhook ? null : _testWebhook,
                      icon: _testingWebhook
                          ? SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2,
                                  color: AppColors.onSurfaceVariant))
                          : Icon(Icons.send_outlined, size: 16, color: AppColors.onSurfaceVariant),
                      label: Text('Test', style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _savingWebhook ? null : _saveWebhook,
                      icon: _savingWebhook
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 16, color: Colors.white),
                      label: const Text('Save URL'),
                    ),
                  ),
                ]),
                if (_webhookStatus != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(
                      _webhookStatus == 'Saved' ? Icons.check_circle_outline : Icons.info_outline,
                      size: 14,
                      color: _webhookStatus == 'Saved' ? AppColors.statusDone : AppColors.gold,
                    ),
                    const SizedBox(width: 6),
                    Text(_webhookStatus!,
                      style: AppTextStyles.bodySm.copyWith(
                        color: _webhookStatus == 'Saved' ? AppColors.statusDone : AppColors.gold)),
                  ]),
                ],
                const SizedBox(height: 16),
              ]),
            ),
            const Divider(height: 1),
          ],

          // Preferences
          const _SectionTitle(title: 'PREFERENCES'),
          SwitchListTile(
            value: _pushNotifs,
            onChanged: (v) => setState(() => _pushNotifs = v),
            title: Text('Push Notifications', style: AppTextStyles.bodyMd),
            subtitle: Text('Receive alerts in real-time', style: AppTextStyles.bodySm),
            secondary: const Icon(Icons.notifications_outlined, color: AppColors.gold),
            activeColor: AppColors.gold, activeTrackColor: AppColors.primary,
          ),
          SwitchListTile(
            value: _emailDigest,
            onChanged: (v) => setState(() => _emailDigest = v),
            title: Text('Email Digest', style: AppTextStyles.bodyMd),
            subtitle: Text('Daily summary via email', style: AppTextStyles.bodySm),
            secondary: const Icon(Icons.email_outlined, color: AppColors.gold),
            activeColor: AppColors.gold, activeTrackColor: AppColors.primary,
          ),
          SwitchListTile(
            value: context.watch<ThemeController>().isDark,
            onChanged: (v) => context.read<ThemeController>().setDark(v),
            title: Text('Dark Mode', style: AppTextStyles.bodyMd),
            subtitle: Text('Switch between light and dark theme', style: AppTextStyles.bodySm),
            secondary: const Icon(Icons.dark_mode_outlined, color: AppColors.gold),
            activeColor: AppColors.gold, activeTrackColor: AppColors.primary,
          ),
          ListTile(
            leading: const Icon(Icons.language, color: AppColors.gold),
            title: Text(S.t('language'), style: AppTextStyles.bodyMd),
            subtitle: Text(
              context.watch<LocaleController>().isArabic ? 'العربية' : 'English',
              style: AppTextStyles.bodySm,
            ),
            trailing: Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 16),
                Text(S.t('language'), style: AppTextStyles.headlineSm),
                const Divider(),
                ...[('en', 'English'), ('ar', 'العربية')].map((l) => ListTile(
                  title: Text(l.$2, style: AppTextStyles.bodyMd),
                  trailing: context.read<LocaleController>().locale.languageCode == l.$1
                      ? const Icon(Icons.check, color: AppColors.gold)
                      : null,
                  onTap: () {
                    context.read<LocaleController>().setLanguage(l.$1);
                    Navigator.pop(context);
                  },
                )),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          const Divider(height: 1),

          // About
          const _SectionTitle(title: 'ABOUT'),
          const _SettingsTile(icon: Icons.info_outlined, title: 'App Version', subtitle: '1.0.0+1'),
          _SettingsTile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () {}),
          _SettingsTile(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () {}),
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
                label: Text('Sign Out',
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.statusHigh)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.statusHigh),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ]),
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
  const _SettingsTile({required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.gold),
    title: Text(title, style: AppTextStyles.bodyMd),
    subtitle: subtitle != null ? Text(subtitle!, style: AppTextStyles.bodySm) : null,
    trailing: onTap != null ? Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant) : null,
    onTap: onTap,
  );
}
