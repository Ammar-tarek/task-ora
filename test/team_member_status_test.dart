// test/team_member_status_test.dart
// TeamMember status model: active/inactive flags + the active-only Team Size
// count used by the Team screen and dashboard.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/features/team/team_performance_repository.dart';

void main() {
  group('TeamMember status', () {
    test('isActive reflects status; default is active', () {
      const active = TeamMember(id: '1', name: 'A', role: 'employee');
      const inactive =
          TeamMember(id: '2', name: 'B', role: 'employee', status: 'inactive');
      expect(active.isActive, isTrue);
      expect(inactive.isActive, isFalse);
    });

    test('isAdmin covers role=admin and the super-admin flag', () {
      const admin = TeamMember(id: '1', name: 'A', role: 'admin');
      const superAdmin = TeamMember(
          id: '2', name: 'S', role: 'employee', isSuperAdmin: true);
      const employee = TeamMember(id: '3', name: 'E', role: 'employee');
      expect(admin.isAdmin, isTrue);
      expect(superAdmin.isAdmin, isTrue);
      expect(employee.isAdmin, isFalse);
    });

    test('activeCount counts active members only (Team Size active-only)', () {
      final members = [
        const TeamMember(id: '1', name: 'A', role: 'employee'),
        const TeamMember(id: '2', name: 'B', role: 'employee', status: 'inactive'),
        const TeamMember(id: '3', name: 'C', role: 'admin'),
        const TeamMember(id: '4', name: 'D', role: 'employee', status: 'inactive'),
      ];
      // 4 members kept in the list, but only 2 are active.
      expect(members.length, 4);
      expect(TeamMember.activeCount(members), 2);
    });

    test('inactive members are still present in the list (badge rendering)', () {
      final members = [
        const TeamMember(id: '1', name: 'A', role: 'employee'),
        const TeamMember(id: '2', name: 'B', role: 'employee', status: 'inactive'),
      ];
      expect(members.where((m) => !m.isActive).map((m) => m.id), ['2']);
    });
  });
}
