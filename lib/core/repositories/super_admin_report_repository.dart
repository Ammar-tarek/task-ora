// lib/core/repositories/super_admin_report_repository.dart
// Comprehensive detailed metrics and log items for Super Admin Master Report.

import '../services/supabase_service.dart';

class TaskAssigneeInfo {
  final String profileId;
  final String name;
  final bool isLead;
  const TaskAssigneeInfo({
    required this.profileId,
    required this.name,
    required this.isLead,
  });
}

class DetailedTaskReportItem {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final int completionPercentage;
  final double? cost;
  final String? clientName;
  final String? teamName;
  final String? department;
  final String? dueDate;
  final String? createdAt;
  final List<TaskAssigneeInfo> assignees;
  final List<CommentReportItem> comments;

  const DetailedTaskReportItem({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.completionPercentage,
    this.cost,
    this.clientName,
    this.teamName,
    this.department,
    this.dueDate,
    this.createdAt,
    required this.assignees,
    required this.comments,
  });
}

class AttendanceReportItem {
  final String id;
  final String userName;
  final String date;
  final String? checkIn;
  final String? checkOut;
  final String status;
  final double hoursWorked;
  final bool isManual;

  const AttendanceReportItem({
    required this.id,
    required this.userName,
    required this.date,
    this.checkIn,
    this.checkOut,
    required this.status,
    required this.hoursWorked,
    required this.isManual,
  });
}

class CrmReportItem {
  final String id;
  final String title;
  final String clientName;
  final double amount;
  final double paidAmount;
  final String status;
  final String sourceType;
  final String? dueDate;
  final String? invoiceNumber;

  const CrmReportItem({
    required this.id,
    required this.title,
    required this.clientName,
    required this.amount,
    required this.paidAmount,
    required this.status,
    required this.sourceType,
    this.dueDate,
    this.invoiceNumber,
  });

  double get outstanding => amount - paidAmount;
}

class DetailedExpenseItem {
  final String id;
  final String categoryName;
  final double amount;
  final String date;
  final String description;
  final String recordedByName;
  final String status;

  const DetailedExpenseItem({
    required this.id,
    required this.categoryName,
    required this.amount,
    required this.date,
    required this.description,
    required this.recordedByName,
    required this.status,
  });
}

class PenaltyReportItem {
  final String id;
  final String employeeName;
  final double amount;
  final String reason;
  final String date;
  final String status;

  const PenaltyReportItem({
    required this.id,
    required this.employeeName,
    required this.amount,
    required this.reason,
    required this.date,
    required this.status,
  });
}

class ExpenseCategoryReportItem {
  final String categoryName;
  final double totalAmount;
  final int count;

  const ExpenseCategoryReportItem({
    required this.categoryName,
    required this.totalAmount,
    required this.count,
  });
}

class CommentReportItem {
  final String id;
  final String taskId;
  final String authorName;
  final String taskTitle;
  final String content;
  final String createdAt;

  const CommentReportItem({
    required this.id,
    required this.taskId,
    required this.authorName,
    required this.taskTitle,
    required this.content,
    required this.createdAt,
  });
}

class SuperAdminReportData {
  // Tasks
  final int totalTasks;
  final Map<String, int> tasksByStatus;
  final Map<String, int> tasksByPriority;
  final List<DetailedTaskReportItem> taskList;

  // Attendance
  final int totalAttendanceRecords;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final double totalHoursWorked;
  final List<AttendanceReportItem> attendanceList;

  // Finance & CRM
  final double totalRevenue;
  final double totalPaidRevenue;
  final List<CrmReportItem> crmList;

  // Expenses & Penalties
  final double totalExpenses;
  final double totalPenalties;
  final List<DetailedExpenseItem> expenseList;
  final List<ExpenseCategoryReportItem> expenseCategories;
  final List<PenaltyReportItem> penaltyList;

  // Comments
  final int totalComments;
  final List<CommentReportItem> commentsList;

  const SuperAdminReportData({
    required this.totalTasks,
    required this.tasksByStatus,
    required this.tasksByPriority,
    required this.taskList,
    required this.totalAttendanceRecords,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.totalHoursWorked,
    required this.attendanceList,
    required this.totalRevenue,
    required this.totalPaidRevenue,
    required this.crmList,
    required this.totalExpenses,
    required this.totalPenalties,
    required this.expenseList,
    required this.expenseCategories,
    required this.penaltyList,
    required this.totalComments,
    required this.commentsList,
  });

  double get netBalance => totalRevenue - totalExpenses - totalPenalties;
}

class SuperAdminReportRepository {
  static final _admin = SupabaseService.adminClient;

  static Future<SuperAdminReportData> fetchMasterReport() async {
    // 1. Profiles Mapping
    final Map<String, String> userNames = {};
    try {
      final profilesData = await _admin.from('profiles').select('id, full_name');
      for (final p in profilesData) {
        userNames[p['id'] as String] = p['full_name'] as String? ?? 'Unknown User';
      }
    } catch (_) {}

    // 2. Teams Mapping
    final Map<String, String> teamNames = {};
    final Map<String, String> teamDepts = {};
    try {
      final teamsData = await _admin.from('teams').select('id, name, department');
      for (final tm in teamsData) {
        final id = tm['id'] as String;
        final name = tm['name'] as String? ?? 'Team';
        final dept = tm['department'] as String?;
        teamNames[id] = name;
        teamDepts[id] = dept ?? 'General';
      }
    } catch (_) {}

    // 3. Comments
    List<dynamic> commentsData = [];
    try {
      commentsData = await _admin
          .from('task_comments')
          .select('id, task_id, user_id, content, created_at')
          .order('created_at', ascending: false);
    } catch (_) {}

    // 4. Tasks Query
    List<dynamic> tasksData = [];
    try {
      tasksData = await _admin
          .from('tasks')
          .select('*, client:client_profiles(company_name), team:teams(name, department), task_assignees(profile_id, is_lead)')
          .order('created_at', ascending: false);
    } catch (_) {
      try {
        tasksData = await _admin.from('tasks').select('*').order('created_at', ascending: false);
      } catch (_) {}
    }

    // Map task titles
    final Map<String, String> taskTitles = {};
    for (final t in tasksData) {
      final id = t['id'] as String?;
      if (id != null) {
        taskTitles[id] = t['title'] as String? ?? 'Untitled Task';
      }
    }

    final List<CommentReportItem> commentItems = [];
    for (final c in commentsData) {
      final tid = c['task_id'] as String? ?? '';
      final uid = c['user_id'] as String?;
      final author = userNames[uid] ?? 'User';
      final title = taskTitles[tid] ?? 'Task';
      commentItems.add(
        CommentReportItem(
          id: c['id'] as String? ?? '',
          taskId: tid,
          authorName: author,
          taskTitle: title,
          content: c['content'] as String? ?? '',
          createdAt: c['created_at'] as String? ?? '',
        ),
      );
    }

    final Map<String, int> tasksByStatus = {};
    final Map<String, int> tasksByPriority = {};
    final List<DetailedTaskReportItem> taskList = [];

    for (final t in tasksData) {
      final taskId = t['id'] as String? ?? '';
      final st = t['status'] as String? ?? 'todo';
      final pr = t['priority'] as String? ?? 'medium';
      tasksByStatus[st] = (tasksByStatus[st] ?? 0) + 1;
      tasksByPriority[pr] = (tasksByPriority[pr] ?? 0) + 1;

      final teamObj = t['team'] as Map<String, dynamic>?;
      final teamId = t['team_id'] as String?;
      final teamName = teamObj?['name'] as String? ?? (teamId != null ? teamNames[teamId] : null);
      final dept = teamObj?['department'] as String? ?? (teamId != null ? teamDepts[teamId] : null);

      final clientObj = t['client'] as Map<String, dynamic>?;
      final clientName = clientObj?['company_name'] as String?;

      // Task Assignees
      final List<TaskAssigneeInfo> assignees = [];
      final rawAssignees = t['task_assignees'] as List?;
      if (rawAssignees != null) {
        for (final a in rawAssignees) {
          final pid = a['profile_id'] as String?;
          if (pid != null) {
            assignees.add(
              TaskAssigneeInfo(
                profileId: pid,
                name: userNames[pid] ?? 'Employee',
                isLead: a['is_lead'] as bool? ?? false,
              ),
            );
          }
        }
      }

      final taskComments = commentItems.where((c) => c.taskId == taskId).toList();

      taskList.add(
        DetailedTaskReportItem(
          id: taskId,
          title: t['title'] as String? ?? 'Untitled Task',
          description: t['description'] as String?,
          status: st,
          priority: pr,
          completionPercentage: (t['completion_percentage'] as num?)?.toInt() ?? 0,
          cost: (t['cost'] as num?)?.toDouble(),
          clientName: clientName,
          teamName: teamName,
          department: dept,
          dueDate: t['due_date'] as String?,
          createdAt: t['created_at'] as String?,
          assignees: assignees,
          comments: taskComments,
        ),
      );
    }

    // 5. Attendance Records Query (using employee_id & joined employee profile)
    List<AttendanceReportItem> attendanceList = [];
    int present = 0;
    int late = 0;
    int absent = 0;
    double hoursWorkedSum = 0;

    try {
      final attData = await _admin
          .from('attendance')
          .select('*, employee:profiles!attendance_employee_id_fkey(full_name)')
          .order('attendance_date', ascending: false);

      for (final a in attData) {
        final empMap = a['employee'] as Map<String, dynamic>?;
        final empId = a['employee_id'] as String?;
        final empName = empMap?['full_name'] as String? ?? (empId != null ? (userNames[empId] ?? 'Employee') : 'Employee');
        final st = (a['status'] as String? ?? 'present').toLowerCase();

        if (st == 'present') present++;
        else if (st == 'late') late++;
        else if (st == 'absent') absent++;

        final hrs = (a['hours_worked'] as num?)?.toDouble() ?? (a['total_hours'] as num?)?.toDouble() ?? 0.0;
        hoursWorkedSum += hrs;

        attendanceList.add(
          AttendanceReportItem(
            id: a['id'] as String? ?? '',
            userName: empName,
            date: a['attendance_date'] as String? ?? '',
            checkIn: a['check_in_time'] as String?,
            checkOut: a['check_out_time'] as String?,
            status: st,
            hoursWorked: hrs,
            isManual: a['is_manual_override'] as bool? ?? a['is_manual'] as bool? ?? false,
          ),
        );
      }
    } catch (_) {
      try {
        final attData = await _admin.from('attendance').select('*').order('attendance_date', ascending: false);
        for (final a in attData) {
          final empId = (a['employee_id'] ?? a['profile_id']) as String?;
          final empName = empId != null ? (userNames[empId] ?? 'Employee') : 'Employee';
          final st = (a['status'] as String? ?? 'present').toLowerCase();

          if (st == 'present') present++;
          else if (st == 'late') late++;
          else if (st == 'absent') absent++;

          final hrs = (a['hours_worked'] as num?)?.toDouble() ?? (a['total_hours'] as num?)?.toDouble() ?? 0.0;
          hoursWorkedSum += hrs;

          attendanceList.add(
            AttendanceReportItem(
              id: a['id'] as String? ?? '',
              userName: empName,
              date: (a['attendance_date'] ?? a['date']) as String? ?? '',
              checkIn: (a['check_in_time'] ?? a['check_in']) as String?,
              checkOut: (a['check_out_time'] ?? a['check_out']) as String?,
              status: st,
              hoursWorked: hrs,
              isManual: (a['is_manual_override'] ?? a['is_manual']) as bool? ?? false,
            ),
          );
        }
      } catch (_) {}
    }

    // 6. Finance / CRM Entries Query
    List<CrmReportItem> crmList = [];
    double revenueSum = 0.0;
    double paidRevenueSum = 0.0;

    try {
      final crmData = await _admin
          .from('crm_entries')
          .select('*, client:client_profiles(company_name)')
          .order('created_at', ascending: false);

      for (final c in crmData) {
        final clientMap = c['client'] as Map<String, dynamic>?;
        final clientName = clientMap?['company_name'] as String? ?? 'Client';
        final amt = (c['amount'] as num?)?.toDouble() ?? (c['contract_value'] as num?)?.toDouble() ?? 0.0;
        final paid = (c['paid_amount'] as num?)?.toDouble() ?? 0.0;

        revenueSum += amt;
        paidRevenueSum += paid;

        crmList.add(
          CrmReportItem(
            id: c['id'] as String? ?? '',
            title: c['title'] as String? ?? 'Financial Entry',
            clientName: clientName,
            amount: amt,
            paidAmount: paid,
            status: c['status'] as String? ?? 'unpaid',
            sourceType: c['source_type'] as String? ?? 'manual',
            dueDate: c['due_date'] as String?,
            invoiceNumber: c['invoice_number'] as String?,
          ),
        );
      }
    } catch (_) {
      try {
        final crmData = await _admin.from('crm_entries').select('*');
        for (final c in crmData) {
          final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
          final paid = (c['paid_amount'] as num?)?.toDouble() ?? 0.0;
          revenueSum += amt;
          paidRevenueSum += paid;
          crmList.add(
            CrmReportItem(
              id: c['id'] as String? ?? '',
              title: c['title'] as String? ?? 'Entry',
              clientName: 'Client',
              amount: amt,
              paidAmount: paid,
              status: c['status'] as String? ?? 'unpaid',
              sourceType: c['source_type'] as String? ?? 'manual',
            ),
          );
        }
      } catch (_) {}
    }

    // 7. Expenses Query
    List<DetailedExpenseItem> expenseList = [];
    double expenseSum = 0.0;
    final Map<String, _CatAcc> catMap = {};

    try {
      final expData = await _admin
          .from('expenses')
          .select('*, category:expense_categories(name), recorder:profiles!expenses_recorded_by_fkey(full_name)')
          .order('expense_date', ascending: false);

      for (final e in expData) {
        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        expenseSum += amt;

        final catObj = e['category'] as Map<String, dynamic>?;
        final catName = catObj?['name'] as String? ?? (e['category'] is String ? e['category'] as String : 'General');
        catMap.putIfAbsent(catName, () => _CatAcc()).add(amt);

        final recorderObj = e['recorder'] as Map<String, dynamic>?;
        final recId = e['recorded_by'] as String?;
        final recorderName = recorderObj?['full_name'] as String? ?? (recId != null ? (userNames[recId] ?? 'User') : 'User');

        expenseList.add(
          DetailedExpenseItem(
            id: e['id'] as String? ?? '',
            categoryName: catName,
            amount: amt,
            date: e['expense_date'] as String? ?? '',
            description: e['description'] as String? ?? '',
            recordedByName: recorderName,
            status: e['status'] as String? ?? 'approved',
          ),
        );
      }
    } catch (_) {
      try {
        final expData = await _admin.from('expenses').select('*');
        for (final e in expData) {
          final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
          expenseSum += amt;
          final catName = (e['category'] as String?) ?? 'General';
          catMap.putIfAbsent(catName, () => _CatAcc()).add(amt);
          expenseList.add(
            DetailedExpenseItem(
              id: e['id'] as String? ?? '',
              categoryName: catName,
              amount: amt,
              date: (e['expense_date'] ?? e['created_at']) as String? ?? '',
              description: e['description'] as String? ?? '',
              recordedByName: 'User',
              status: e['status'] as String? ?? 'approved',
            ),
          );
        }
      } catch (_) {}
    }

    final List<ExpenseCategoryReportItem> expenseCategories = catMap.entries.map((e) {
      return ExpenseCategoryReportItem(
        categoryName: e.key,
        totalAmount: e.value.total,
        count: e.value.count,
      );
    }).toList();

    // 8. Penalties Query
    List<PenaltyReportItem> penaltyList = [];
    double penaltiesSum = 0.0;
    try {
      final penData = await _admin
          .from('penalties')
          .select('*, employee:profiles!penalties_employee_id_fkey(full_name)')
          .order('issue_date', ascending: false);

      for (final p in penData) {
        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        penaltiesSum += amt;

        final empObj = p['employee'] as Map<String, dynamic>?;
        final empId = p['employee_id'] as String?;
        final empName = empObj?['full_name'] as String? ?? (empId != null ? (userNames[empId] ?? 'Employee') : 'Employee');

        penaltyList.add(
          PenaltyReportItem(
            id: p['id'] as String? ?? '',
            employeeName: empName,
            amount: amt,
            reason: p['reason'] as String? ?? 'Penalty',
            date: p['issue_date'] as String? ?? '',
            status: p['status'] as String? ?? 'active',
          ),
        );
      }
    } catch (_) {
      try {
        final penData = await _admin.from('penalties').select('*');
        for (final p in penData) {
          final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
          penaltiesSum += amt;
          final empId = p['employee_id'] as String?;
          final empName = empId != null ? (userNames[empId] ?? 'Employee') : 'Employee';
          penaltyList.add(
            PenaltyReportItem(
              id: p['id'] as String? ?? '',
              employeeName: empName,
              amount: amt,
              reason: p['reason'] as String? ?? 'Penalty',
              date: (p['issue_date'] ?? p['created_at']) as String? ?? '',
              status: p['status'] as String? ?? 'active',
            ),
          );
        }
      } catch (_) {}
    }

    return SuperAdminReportData(
      totalTasks: tasksData.length,
      tasksByStatus: tasksByStatus,
      tasksByPriority: tasksByPriority,
      taskList: taskList,
      totalAttendanceRecords: attendanceList.length,
      presentCount: present,
      lateCount: late,
      absentCount: absent,
      totalHoursWorked: hoursWorkedSum,
      attendanceList: attendanceList,
      totalRevenue: revenueSum,
      totalPaidRevenue: paidRevenueSum,
      crmList: crmList,
      totalExpenses: expenseSum,
      totalPenalties: penaltiesSum,
      expenseList: expenseList,
      expenseCategories: expenseCategories,
      penaltyList: penaltyList,
      totalComments: commentItems.length,
      commentsList: commentItems,
    );
  }
}

class _CatAcc {
  double total = 0.0;
  int count = 0;
  void add(double amt) {
    total += amt;
    count++;
  }
}
