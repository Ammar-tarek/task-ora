// lib/features/tasks/employee_status_workflow.dart
// Pure rule for which task statuses an EMPLOYEE may set, and the clean set a
// Montage employee sees in the Update Status modal.
//
// Workflow: an employee's "finished" action is 'employee_done' — it does NOT
// mark the task 'completed'. Only a manager confirms completion → 'completed'.
// So 'completed' is never in the employee-settable set, and monthly progress
// (which counts persisted status == 'completed') only moves on manager confirm.

import '../../core/models/task_status_option.dart';

class EmployeeStatusWorkflow {
  EmployeeStatusWorkflow._();

  /// Built-in workflow states an employee may set. 'completed' is intentionally
  /// excluded (manager-confirmed), as are client_* and other admin/manager states.
  static const Set<String> allowed = {
    'not_started',
    'in_progress',
    'employee_done',
    'on_hold',
  };

  /// True when an employee is allowed to set [statusLabel] themselves.
  static bool employeeCanSet(String statusLabel) => allowed.contains(statusLabel);

  /// Options a MONTAGE employee sees in Update Status: only the built-in
  /// allowed workflow states — no custom options, no manager/admin states,
  /// never 'completed'. Keeps the modal consistent and confirmation-safe.
  static List<TaskStatusOption> montageEmployeeOptions(
    List<TaskStatusOption> all,
  ) =>
      all.where((o) => o.isDefault && allowed.contains(o.label)).toList();
}
