// lib/features/roles/roles_editor_screen.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/data/mock_data.dart';

class RolesEditorScreen extends StatefulWidget {
  const RolesEditorScreen({super.key});
  @override
  State<RolesEditorScreen> createState() => _RolesEditorScreenState();
}

class _RolesEditorScreenState extends State<RolesEditorScreen> {
  int _selectedRole = 0;
  late final List<List<bool>> _perms;

  @override
  void initState() {
    super.initState();
    // Pre-populate: Admin has all, others have some
    _perms = List.generate(MockData.roles.length, (i) =>
      List.generate(MockData.permissions.length, (j) => i == 0 || j < 3));
  }

  @override
  Widget build(BuildContext context) {
    final role = MockData.roles[_selectedRole];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Roles & Privileges')),
      body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Role list
        Container(
          width: 120,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            border: Border(right: BorderSide(color: AppColors.outlineVariant)),
          ),
          child: ListView.builder(
            itemCount: MockData.roles.length,
            itemBuilder: (_, i) {
              final r = MockData.roles[i];
              final isSelected = i == _selectedRole;
              return GestureDetector(
                onTap: () => setState(() => _selectedRole = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: isSelected
                        ? const Border(left: BorderSide(color: AppColors.gold, width: 3))
                        : null,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['name'] as String,
                      style: AppTextStyles.labelMd.copyWith(
                        color: isSelected ? Colors.white : AppColors.onSurface,
                        fontSize: 12,
                      ),
                    ),
                    Text('${r['count']} users',
                      style: AppTextStyles.bodySm.copyWith(
                        color: isSelected ? Colors.white54 : null, fontSize: 10,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        // Permissions
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: Color(role['color'] as int), shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(role['name'] as String, style: AppTextStyles.headlineSm),
              ]),
              Text('${role['count']} users with this role',
                style: AppTextStyles.bodySm),
              const SizedBox(height: 20),
              Text('PERMISSIONS', style: AppTextStyles.labelCaps),
              const SizedBox(height: 8),
              ...List.generate(MockData.permissions.length, (j) => SwitchListTile(
                value: _perms[_selectedRole][j],
                onChanged: _selectedRole == 0 ? null : (v) => setState(() => _perms[_selectedRole][j] = v),
                title: Text(MockData.permissions[j], style: AppTextStyles.bodyMd),
                subtitle: _selectedRole == 0
                    ? Text('Always enabled for Admin', style: AppTextStyles.bodySm) : null,
                activeColor: AppColors.gold,
                activeTrackColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
              )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedRole == 0 ? null : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${role['name']} permissions saved!')),
                    );
                  },
                  child: const Text('Save Permissions'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
