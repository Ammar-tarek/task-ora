// lib/features/tasks/montage_completion.dart
// Montage manager-confirmation rule. An employee's "Employee Done"
// (status 'employee_done') is NOT completion — a manager/admin confirms it,
// which flips the persisted status to the enum value 'completed'. Only then
// does the employee's monthly progress (which counts 'completed') move.

class MontageCompletion {
  MontageCompletion._();

  /// The enum value a confirmed task lands on.
  static const String confirmedStatus = 'completed';

  /// The status a task must be in to be awaiting confirmation.
  static const String pendingStatus = 'employee_done';

  /// True when the current user may confirm completion of this task:
  /// a Montage task, the viewer can edit fully (manager/admin/super), and the
  /// task is awaiting confirmation. Employees never qualify.
  static bool managerCanConfirm({
    required bool isMontage,
    required bool canEditFull,
    required String status,
  }) =>
      isMontage && canEditFull && status == pendingStatus;
}
