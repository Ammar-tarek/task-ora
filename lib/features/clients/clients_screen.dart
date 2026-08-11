// lib/features/clients/clients_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/locale_controller.dart';
import '../../core/models/client_model.dart';
import '../../core/providers/team_privileges_notifier.dart';
import '../../core/repositories/client_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<ClientModel> _clients = [];
  bool _loading = true;
  String? _managerDepartment; // null = admin — show all clients

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthNotifier>().profile;
    if (profile?.isManager == true && profile?.teamId != null) {
      final team = await TeamRepository.fetchById(profile!.teamId!);
      _managerDepartment = team?.department?.toLowerCase();
    }
    final clients = await ClientRepository.fetchClients(
      clientType: _managerDepartment,
    );
    if (mounted) {
      setState(() {
        _clients = clients;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<LocaleController, Locale>((l) => l.locale);
    final profile = context.select<AuthNotifier, dynamic>((a) => a.profile);
    final isAdmin = profile?.isAdmin ?? false;
    final canCreate = isAdmin || context.select<TeamPrivilegesNotifier, bool>((p) => p.canManageClients);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(S.t('clients')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Create client',
              onPressed: () => _showCreateSheet(context),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
          ? _EmptyClients(
              canCreate: canCreate,
              onCreate: () => _showCreateSheet(context),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _clients.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ClientCard(
                  client: _clients[i],
                  isAdmin: isAdmin,
                  onTap: () =>
                      context.push('/clients/${_clients[i].id}/finance'),
                  onEdit: () => _showEditSheet(context, _clients[i]),
                  onDelete: isAdmin
                      ? () => _confirmDeleteClient(_clients[i])
                      : null,
                ),
              ),
            ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateSheet(context),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: AppColors.gold),
              label: const Text(
                'New Client',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CreateClientSheet(
        onCreated: _load,
        presetClientType: _managerDepartment,
      ),
    );
  }

  void _showEditSheet(BuildContext context, ClientModel client) {
    final profile = context.read<AuthNotifier>().profile;
    final isAdmin = profile?.isAdmin ?? false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EditClientSheet(
        client: client,
        isAdmin: isAdmin,
        onSaved: _load,
        onDelete: isAdmin ? () => _confirmDeleteClient(client) : null,
      ),
    );
  }

  Future<void> _confirmDeleteClient(ClientModel client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        title: const Text('Delete Client?'),
        content: Text(
          'Are you sure you want to delete "${client.companyName}"?\n\n'
          'This will permanently remove the client account and profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusHigh,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Client'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _loading = true);
      final res = await ClientRepository.deleteClient(client.id);
      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Client "${client.companyName}" removed.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text(res.error ?? 'Failed to delete client.'),
          ),
        );
      }
      _load();
    }
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class _EmptyClients extends StatelessWidget {
  const _EmptyClients({required this.canCreate, required this.onCreate});
  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.business_outlined,
              size: 64,
              color: AppColors.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No clients yet',
              style: AppTextStyles.headlineSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              canCreate
                  ? 'Create your first client to link tasks, meetings, and invoices.'
                  : 'An admin must create clients before they appear here.',
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (canCreate) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create Client'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Client card ────────────────────────────────────────────────────────────────
class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.onTap,
    required this.onEdit,
    this.isAdmin = false,
    this.onDelete,
  });
  final ClientModel client;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final bool isAdmin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                client.initials,
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.gold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          client.companyName,
                          style: AppTextStyles.labelMd,
                        ),
                      ),
                      if (client.clientType.isNotEmpty &&
                          client.clientType != 'general') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            client.clientType,
                            style: AppTextStyles.labelCaps.copyWith(
                              color: AppColors.gold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    client.contactPerson,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    client.email,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.onSurfaceVariant,
              ),
              tooltip: 'Edit client',
              onPressed: onEdit,
            ),
            if (isAdmin && onDelete != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.error,
                ),
                tooltip: 'Delete client',
                onPressed: onDelete,
              ),
            Icon(Icons.chevron_right, color: AppColors.outlineVariant),
          ],
        ),
      ),
    );
  }
}

// ── Create client bottom sheet ─────────────────────────────────────────────────
class _CreateClientSheet extends StatefulWidget {
  const _CreateClientSheet({required this.onCreated, this.presetClientType});
  final VoidCallback onCreated;
  final String? presetClientType;

  @override
  State<_CreateClientSheet> createState() => _CreateClientSheetState();
}

class _CreateClientSheetState extends State<_CreateClientSheet> {
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _saving = false;
  List<String> _departments = [];
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.presetClientType?.toLowerCase();
    // Seed with the current value so the dropdown always has a matching item.
    if (_selectedType != null && _selectedType!.isNotEmpty) {
      _departments = [_selectedType!];
    }
    loadClientDepartments().then((d) {
      if (!mounted) return;
      setState(() {
        _departments = {..._departments, ...d}.toList()..sort();
      });
    });
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _companyCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_fullNameCtrl.text.trim().isEmpty) return 'Full name is required';
    if (_emailCtrl.text.trim().isEmpty) return 'Email is required';
    if (_passwordCtrl.text.length < 6) {
      return 'Password must be at least 6 characters';
    }
    if (_companyCtrl.text.trim().isEmpty) return 'Company name is required';
    if (_contactCtrl.text.trim().isEmpty) return 'Contact person is required';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _saving = true);

    final result = await ClientRepository.createClientWithAccount(
      fullName: _fullNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      companyName: _companyCtrl.text.trim(),
      contactPerson: _contactCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      whatsappNumber: _whatsappCtrl.text.trim().isEmpty
          ? null
          : _whatsappCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      clientType: _selectedType,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.client != null) {
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Client "${result.client!.companyName}" created'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to create client')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      child: Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('New Client', style: AppTextStyles.headlineSm),
            const SizedBox(height: 4),
            Text(
              'Creates a login account and company profile',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // ── Account section ──────────────────────────────────────
            _SectionLabel(label: 'LOGIN ACCOUNT'),
            const SizedBox(height: 10),
            _Field(
              controller: _fullNameCtrl,
              label: 'Full name *',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _emailCtrl,
              label: 'Email *',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password *',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Company section ──────────────────────────────────────
            _SectionLabel(label: 'COMPANY DETAILS'),
            const SizedBox(height: 10),
            _Field(
              controller: _companyCtrl,
              label: 'Company name *',
              icon: Icons.business_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _contactCtrl,
              label: 'Contact person *',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _phoneCtrl,
              label: 'Phone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _whatsappCtrl,
              label: 'WhatsApp number',
              icon: Icons.chat_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _addressCtrl,
              label: 'Address',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _notesCtrl,
              label: 'Notes',
              icon: Icons.notes_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // ── Client type section ──────────────────────────────────
            _SectionLabel(label: 'DEPARTMENT'),
            const SizedBox(height: 10),
            _DepartmentDropdown(
              departments: _departments,
              value: _selectedType,
              // Managers create clients only within their own department.
              enabled: widget.presetClientType == null,
              onChanged: (v) => setState(() => _selectedType = v),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      )
                    : Text(
                        'Create Client Account',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

// ── Edit client bottom sheet ───────────────────────────────────────────────────
class _EditClientSheet extends StatefulWidget {
  const _EditClientSheet({
    required this.client,
    required this.onSaved,
    this.isAdmin = false,
    this.onDelete,
  });
  final ClientModel client;
  final VoidCallback onSaved;
  final bool isAdmin;
  final VoidCallback? onDelete;

  @override
  State<_EditClientSheet> createState() => _EditClientSheetState();
}

class _EditClientSheetState extends State<_EditClientSheet> {
  late final _fullNameCtrl = TextEditingController();
  late final _emailCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  late final _companyCtrl = TextEditingController();
  late final _contactCtrl = TextEditingController();
  late final _phoneCtrl = TextEditingController();
  late final _whatsappCtrl = TextEditingController();
  late final _addressCtrl = TextEditingController();
  late final _notesCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _saving = false;
  List<String> _departments = [];
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    // Pre-fill with existing data — full_name fetched from profiles
    _loadFullName();
    _emailCtrl.text = c.email;
    _companyCtrl.text = c.companyName;
    _contactCtrl.text = c.contactPerson;
    _phoneCtrl.text = c.phone ?? '';
    _whatsappCtrl.text = c.whatsappNumber ?? '';
    _addressCtrl.text = c.address ?? '';
    _notesCtrl.text = c.notes ?? '';
    final existing = c.clientType.toLowerCase();
    _selectedType = (existing.isEmpty || existing == 'general')
        ? null
        : existing;
    // Seed with the current value so the dropdown always has a matching item.
    if (_selectedType != null) _departments = [_selectedType!];
    loadClientDepartments().then((d) {
      if (!mounted) return;
      setState(() {
        _departments = {..._departments, ...d}.toList()..sort();
      });
    });
  }

  Future<void> _loadFullName() async {
    try {
      final data = await ClientRepository.adminDb
          .from('profiles')
          .select('full_name')
          .eq('id', widget.client.id)
          .single();
      if (mounted) _fullNameCtrl.text = data['full_name'] as String? ?? '';
    } catch (_) {}
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _newPasswordCtrl.dispose();
    _companyCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_fullNameCtrl.text.trim().isEmpty) return 'Full name is required';
    if (_emailCtrl.text.trim().isEmpty) return 'Email is required';
    if (_companyCtrl.text.trim().isEmpty) return 'Company name is required';
    if (_contactCtrl.text.trim().isEmpty) return 'Contact person is required';
    if (_newPasswordCtrl.text.isNotEmpty && _newPasswordCtrl.text.length < 6) {
      return 'New password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _saving = true);

    final result = await ClientRepository.updateClientWithAccount(
      clientId: widget.client.id,
      fullName: _fullNameCtrl.text.trim(),
      email: widget.client.email,
      newEmail: _emailCtrl.text.trim(),
      newPassword: _newPasswordCtrl.text.isEmpty ? null : _newPasswordCtrl.text,
      companyName: _companyCtrl.text.trim(),
      contactPerson: _contactCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      whatsappNumber: _whatsappCtrl.text.trim().isEmpty
          ? null
          : _whatsappCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      clientType: _selectedType,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result.client != null) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Client "${result.client!.companyName}" updated'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Failed to update client')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      child: Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Edit Client', style: AppTextStyles.headlineSm),
            const SizedBox(height: 20),

            // ── Account section ──────────────────────────────────────
            _SectionLabel(label: 'LOGIN ACCOUNT'),
            const SizedBox(height: 10),
            _Field(
              controller: _fullNameCtrl,
              label: 'Full name *',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _emailCtrl,
              label: 'Email *',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'New password (leave blank to keep current)',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Company section ──────────────────────────────────────
            _SectionLabel(label: 'COMPANY DETAILS'),
            const SizedBox(height: 10),
            _Field(
              controller: _companyCtrl,
              label: 'Company name *',
              icon: Icons.business_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _contactCtrl,
              label: 'Contact person *',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _phoneCtrl,
              label: 'Phone',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _whatsappCtrl,
              label: 'WhatsApp number',
              icon: Icons.chat_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _addressCtrl,
              label: 'Address',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _notesCtrl,
              label: 'Notes',
              icon: Icons.notes_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // ── Client type section ──────────────────────────────────
            _SectionLabel(label: 'DEPARTMENT'),
            const SizedBox(height: 10),
            _DepartmentDropdown(
              departments: _departments,
              value: _selectedType,
              onChanged: (v) => setState(() => _selectedType = v),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      )
                    : Text(
                        'Save Changes',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            if (widget.isAdmin && widget.onDelete != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDelete?.call();
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.error,
                  ),
                  label: const Text(
                    'Delete Client',
                    style: TextStyle(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: AppTextStyles.labelCaps.copyWith(
        color: AppColors.onSurfaceVariant,
        fontSize: 11,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}

// ── Department helpers ────────────────────────────────────────────────────────

/// Distinct team departments (lowercased), used as the client "department" /
/// client_type options so clients map to the same departments as teams.
Future<List<String>> loadClientDepartments() async {
  try {
    final teams = await TeamRepository.fetchAll();
    final set = <String>{};
    for (final t in teams) {
      final d = t.department?.trim();
      if (d != null && d.isNotEmpty) set.add(d.toLowerCase());
    }
    final list = set.toList()..sort();
    return list;
  } catch (_) {
    return [];
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Dropdown of departments for selecting a client's department (client_type).
class _DepartmentDropdown extends StatelessWidget {
  const _DepartmentDropdown({
    required this.departments,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final List<String> departments;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Department',
        prefixIcon: const Icon(Icons.apartment_outlined, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: !enabled,
        fillColor: !enabled
            ? AppColors.outlineVariant.withValues(alpha: 0.12)
            : null,
      ),
      hint: const Text('Select department'),
      items: [
        ...departments
            .where((d) => d != 'both')
            .map((d) => DropdownMenuItem(value: d, child: Text(_titleCase(d)))),
        const DropdownMenuItem(value: 'both', child: Text('Both Departments')),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
