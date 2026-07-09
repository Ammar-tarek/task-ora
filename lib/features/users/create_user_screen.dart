// lib/features/users/create_user_screen.dart
// Admin: two tabs — create a new manager account OR promote an existing employee.
// Manager: single form to create a new employee account.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/models/profile_model.dart';
import '../../core/repositories/profile_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/theme/app_theme.dart';

class CreateUserScreen extends StatefulWidget {
  /// The team the new/promoted user will be auto-assigned to.
  /// Passed from UserManagementScreen when a team is already selected.
  final String? teamId;
  final String? teamName;

  const CreateUserScreen({super.key, this.teamId, this.teamName});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  // ── New-account form ────────────────────────────────────────────────────
  final _formKey   = GlobalKey<FormState>();
  final _namCtrl   = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool    _saving       = false;
  bool    _obscurePass  = true;
  String? _errorMsg;
  String? _successMsg;

  // ── Tab selector (admin only) ────────────────────────────────────────────
  int _tab = 0; // 0 = New Account, 1 = Promote Employee

  // ── Promote-employee tab ─────────────────────────────────────────────────
  bool              _loadingEmployees = false;
  List<ProfileModel> _employees        = [];
  List<ProfileModel> _filteredEmployees= [];
  final _promoteSearch = TextEditingController();
  String? _promotingId;
  String? _promoteError;
  String? _promoteSuccess;

  @override
  void initState() {
    super.initState();
    _promoteSearch.addListener(_filterEmployees);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<AuthNotifier>().profile?.isAdmin == true) {
        _loadEmployees();
      }
    });
  }

  @override
  void dispose() {
    _namCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _promoteSearch.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String get _targetRole {
    final role = context.read<AuthNotifier>().profile?.role;
    return role == 'admin' ? 'manager' : 'employee';
  }

  // ── New account form logic ───────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _errorMsg = null; _successMsg = null; });

    final role  = _targetRole;
    final email = _emailCtrl.text.trim();
    final error = await ProfileRepository.createUser(
      email:    email,
      password: _passCtrl.text,
      fullName: _namCtrl.text.trim(),
      role:     role,
      teamId:   widget.teamId,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() { _saving = false; _errorMsg = error; });
    } else {
      final teamSuffix = widget.teamName != null
          ? ' and assigned to ${widget.teamName}.'
          : '.';
      setState(() {
        _saving     = false;
        _successMsg = '${role == 'manager' ? 'Manager' : 'Employee'} account '
            'created for $email$teamSuffix';
      });
      _namCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
    }
  }

  // ── Promote tab logic ────────────────────────────────────────────────────

  Future<void> _loadEmployees() async {
    setState(() => _loadingEmployees = true);
    final list = await ProfileRepository.fetchPromotable();
    if (!mounted) return;
    setState(() {
      _employees         = list;
      _filteredEmployees = list;
      _loadingEmployees  = false;
    });
  }

  void _filterEmployees() {
    final q = _promoteSearch.text.toLowerCase();
    setState(() {
      _filteredEmployees = q.isEmpty
          ? List.of(_employees)
          : _employees
              .where((e) => e.fullName.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _promote(ProfileModel employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Promote to Manager?', style: AppTextStyles.headlineSm),
        content: Text(
          '${employee.fullName} will become a manager and gain team management capabilities.',
          style: AppTextStyles.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppTextStyles.labelMd),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Promote'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _promotingId    = employee.id;
      _promoteError   = null;
      _promoteSuccess = null;
    });

    final error = await ProfileRepository.updateRole(employee.id, 'manager');
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _promoteError = error;
        _promotingId  = null;
      });
    } else {
      // Auto-assign the newly promoted manager to the current team
      if (widget.teamId != null) {
        await TeamRepository.setTeamForUser(employee.id, widget.teamId);
      }
      if (!mounted) return;
      final teamSuffix = widget.teamName != null
          ? ' and assigned to ${widget.teamName}.'
          : '.';
      setState(() {
        _promoteSuccess = '${employee.fullName} has been promoted to Manager$teamSuffix';
        _promotingId    = null;
        _employees.removeWhere((e) => e.id == employee.id);
        _filteredEmployees.removeWhere((e) => e.id == employee.id);
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AuthNotifier>().profile?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAdmin ? 'Manage Accounts' : 'Create Employee Account'),
        backgroundColor: AppColors.surface,
      ),
      body: Column(
        children: [
          // Header card
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: _buildHeaderCard(isAdmin),
          ),

          // Tab selector (admin only)
          if (isAdmin) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildTabSelector(),
            ),
          ],

          const SizedBox(height: 8),

          // Body
          Expanded(
            child: (!isAdmin || _tab == 0)
                ? _buildNewAccountForm()
                : _buildPromoteTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isAdmin) {
    final isNew = !isAdmin || _tab == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isAdmin
                ? (isNew
                    ? Icons.manage_accounts_outlined
                    : Icons.upgrade_outlined)
                : Icons.person_add_outlined,
            color: AppColors.gold,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAdmin
                    ? (isNew ? 'Create Manager Account' : 'Promote to Manager')
                    : 'Create Employee Account',
                style: AppTextStyles.labelMd,
              ),
              const SizedBox(height: 2),
              Text(
                isAdmin
                    ? (isNew
                        ? 'Creates a brand-new account with manager privileges.'
                        : 'Upgrade an existing employee to manager role.')
                    : 'New account can view and update tasks for their team.',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _TabChip(
          label: 'New Account',
          selected: _tab == 0,
          onTap: () => setState(() => _tab = 0),
        ),
        _TabChip(
          label: 'Promote Employee',
          selected: _tab == 1,
          onTap: () => setState(() => _tab = 1),
        ),
      ]),
    );
  }

  // ── New Account Form ─────────────────────────────────────────────────────

  Widget _buildNewAccountForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success banner
            if (_successMsg != null) ...[
              _Banner(
                message: _successMsg!,
                color: AppColors.statusDone,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 16),
            ],

            // Error banner
            if (_errorMsg != null) ...[
              _Banner(
                message: _errorMsg!,
                color: AppColors.error,
                icon: Icons.error_outline,
              ),
              const SizedBox(height: 16),
            ],

            // Full name
            TextFormField(
              controller: _namCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'FULL NAME *',
                hintText: 'e.g. Sara Ahmed',
                prefixIcon: Icon(Icons.person_outline, size: 18),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Full name is required';
                if (v.trim().length < 2) return 'Name is too short';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'EMAIL ADDRESS *',
                hintText: 'e.g. sara@company.com',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                final re = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                if (!re.hasMatch(v.trim())) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'TEMPORARY PASSWORD *',
                hintText: 'Min 8 characters',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 8) return 'Minimum 8 characters';
                return null;
              },
            ),

            const SizedBox(height: 8),
            Text(
              'Share these credentials directly with the new '
              '${_targetRole == 'manager' ? 'manager' : 'employee'}. '
              'They can change their password after logging in.',
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Create ${_targetRole == 'manager' ? 'Manager' : 'Employee'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Promote Tab ──────────────────────────────────────────────────────────

  Widget _buildPromoteTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Column(
            children: [
              if (_promoteSuccess != null) ...[
                _Banner(
                  message: _promoteSuccess!,
                  color: AppColors.statusDone,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(height: 12),
              ],
              if (_promoteError != null) ...[
                _Banner(
                  message: _promoteError!,
                  color: AppColors.error,
                  icon: Icons.error_outline,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _promoteSearch,
                decoration: const InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingEmployees
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.gold))
              : _filteredEmployees.isEmpty
                  ? _buildEmptyEmployees()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: _filteredEmployees.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final e = _filteredEmployees[i];
                        return _EmployeePromoteCard(
                          employee: e,
                          isPromoting: _promotingId == e.id,
                          onPromote: () => _promote(e),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyEmployees() {
    final hasSearch = _promoteSearch.text.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search_outlined,
              size: 52, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(
            hasSearch ? 'No matching employees' : 'No employees to promote',
            style: AppTextStyles.labelMd,
          ),
          const SizedBox(height: 4),
          Text(
            hasSearch
                ? 'Try a different name'
                : 'All active employees have already been promoted.',
            style: AppTextStyles.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Employee promote card ─────────────────────────────────────────────────────

class _EmployeePromoteCard extends StatelessWidget {
  const _EmployeePromoteCard({
    required this.employee,
    required this.isPromoting,
    required this.onPromote,
  });
  final ProfileModel employee;
  final bool         isPromoting;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(children: [
        TAvatar(name: employee.fullName, size: 40),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employee.fullName,
                  style: AppTextStyles.labelMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                'Employee${employee.teamId != null ? ' · Assigned to team' : ' · Unassigned'}',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        isPromoting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.gold),
              )
            : TextButton(
                onPressed: onPromote,
                style: TextButton.styleFrom(foregroundColor: AppColors.gold),
                child: const Text('Promote'),
              ),
      ]),
    );
  }
}

// ── Shared tab chip ──────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(
              color: selected ? Colors.black : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable banner ──────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });
  final String   message;
  final Color    color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: AppTextStyles.bodySm.copyWith(color: color)),
        ),
      ]),
    );
  }
}
