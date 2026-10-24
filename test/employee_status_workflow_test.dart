// test/employee_status_workflow_test.dart
// Montage employee Update Status options follow the workflow: employee may set
// the allowed states (incl. employee_done) but NEVER 'completed' — manager
// confirms completion. Custom and manager/admin states are not exposed.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/task_status_option.dart';
import 'package:task_ora/features/tasks/employee_status_workflow.dart';

TaskStatusOption _opt(String label, {bool isDefault = true}) => TaskStatusOption(
  id: label,
  columnId: 'c',
  label: label,
  color: '#888888',
  isDefault: isDefault,
);

void main() {
  group('EmployeeStatusWorkflow', () {
    test('employee can set the workflow states, never completed/client/*', () {
      expect(EmployeeStatusWorkflow.employeeCanSet('employee_done'), isTrue);
      expect(EmployeeStatusWorkflow.employeeCanSet('in_progress'), isTrue);
      expect(EmployeeStatusWorkflow.employeeCanSet('not_started'), isTrue);
      expect(EmployeeStatusWorkflow.employeeCanSet('on_hold'), isTrue);
      // Completion is manager-confirmed — never an employee action.
      expect(EmployeeStatusWorkflow.employeeCanSet('completed'), isFalse);
      expect(EmployeeStatusWorkflow.employeeCanSet('client_approved'), isFalse);
      expect(EmployeeStatusWorkflow.employeeCanSet('client_rejected'), isFalse);
      expect(EmployeeStatusWorkflow.allowed, isNot(contains('completed')));
    });

    test('Montage employee options = allowed defaults only (no custom, no completed)', () {
      final all = [
        _opt('not_started'),
        _opt('in_progress'),
        _opt('employee_done'),
        _opt('on_hold'),
        _opt('client_approved'),
        _opt('completed'),
        _opt('Paid', isDefault: false), // custom → must be hidden
        _opt('completed', isDefault: false), // custom look-alike → hidden too
      ];
      final labels = EmployeeStatusWorkflow.montageEmployeeOptions(all)
          .map((o) => o.label)
          .toList();
      expect(labels, ['not_started', 'in_progress', 'employee_done', 'on_hold']);
      expect(labels, isNot(contains('completed')));
      expect(labels, isNot(contains('client_approved')));
      expect(labels, isNot(contains('Paid')));
    });
  });
}
