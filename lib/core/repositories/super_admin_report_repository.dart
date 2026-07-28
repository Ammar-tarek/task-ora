import 'package:flutter/material.dart' show DateTimeRange;
import '../services/supabase_service.dart';

String formatTo12Hour(String? timeStr) {
  if (timeStr == null || timeStr.trim().isEmpty || timeStr == '-') return '-';
  try {
    final dt = DateTime.tryParse(timeStr);
    if (dt != null) {
      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final p = dt.hour >= 12 ? 'PM' : 'AM';
      final m = dt.minute.toString().padLeft(2, '0');
      return '${h.toString().padLeft(2, '0')}:$m $p';
    }
    final parts = timeStr.trim().split(':');
    if (parts.length >= 2) {
      int h = int.parse(parts[0]);
      int m = int.parse(parts[1]);
      final p = h >= 12 ? 'PM' : 'AM';
      h = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $p';
    }
  } catch (_) {}
  return timeStr;
}

class TaskAssigneeInfo {
  final String profileId;
  final String name;
  final bool isLead;
  final bool isPast;
  const TaskAssigneeInfo({
    required this.profileId,
    required this.name,
    required this.isLead,
    this.isPast = false,
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
  final String? clientId;
  final String? teamName;
  final String? department;
  final String? createdByName;
  final String? startDate;
  final String? dueDate;
  final String? createdAt;
  final String? updatedAt;
  final String? attachmentUrl;
  final List<TaskAssigneeInfo> assignees;
  final List<TaskAssigneeInfo> pastAssignees;
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
    this.clientId,
    this.teamName,
    this.department,
    this.createdByName,
    this.startDate,
    this.dueDate,
    this.createdAt,
    this.updatedAt,
    this.attachmentUrl,
    required this.assignees,
    this.pastAssignees = const [],
    required this.comments,
  });
}

class AttendanceReportItem {
  final String id;
  final String employeeId;
  final String userName;
  final String date;
  final String? checkIn;
  final String? checkOut;
  final String status;
  final double hoursWorked;
  final bool isManual;
  final String? dailyReport;
  final String? notes;
  final String? wifiSsid;

  const AttendanceReportItem({
    required this.id,
    required this.employeeId,
    required this.userName,
    required this.date,
    this.checkIn,
    this.checkOut,
    required this.status,
    required this.hoursWorked,
    required this.isManual,
    this.dailyReport,
    this.notes,
    this.wifiSsid,
  });

  String get checkIn12h => formatTo12Hour(checkIn);
  String get checkOut12h => formatTo12Hour(checkOut);
}

class CrmReportItem {
  final String id;
  final String title;
  final String clientName;
  final String? clientId;
  final double amount;
  final double paidAmount;
  final String status;
  final String sourceType;
  final String? dueDate;
  final String? paymentDate;
  final String? invoiceNumber;
  final String? notes;
  final String? createdAt;

  const CrmReportItem({
    required this.id,
    required this.title,
    required this.clientName,
    this.clientId,
    required this.amount,
    required this.paidAmount,
    required this.status,
    required this.sourceType,
    this.dueDate,
    this.paymentDate,
    this.invoiceNumber,
    this.notes,
    this.createdAt,
  });

  double get outstanding => amount - paidAmount;
}

class ClientMeetingReportItem {
  final String id;
  final String clientId;
  final String title;
  final String? description;
  final String startTime;
  final String endTime;
  final String? location;
  final String? meetingNotes;
  final String status;

  const ClientMeetingReportItem({
    required this.id,
    required this.clientId,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.location,
    this.meetingNotes,
    required this.status,
  });
}

class DetailedExpenseItem {
  final String id;
  final String categoryName;
  final double amount;
  final String date;
  final String description;
  final String recordedByName;
  final String status;
  final String? receiptUrl;
  final String? createdAt;

  const DetailedExpenseItem({
    required this.id,
    required this.categoryName,
    required this.amount,
    required this.date,
    required this.description,
    required this.recordedByName,
    required this.status,
    this.receiptUrl,
    this.createdAt,
  });
}

class PenaltyReportItem {
  final String id;
  final String employeeId;
  final String employeeName;
  final double amount;
  final String reason;
  final String date;
  final String status;
  final String? notes;
  final String? createdAt;

  const PenaltyReportItem({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.reason,
    required this.date,
    required this.status,
    this.notes,
    this.createdAt,
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
  final String authorId;
  final String authorName;
  final String taskTitle;
  final String content;
  final String createdAt;

  const CommentReportItem({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.authorName,
    required this.taskTitle,
    required this.content,
    required this.createdAt,
  });
}

class UserReportItem {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String department;
  final String? phone;
  final bool isActive;
  final String? createdAt;

  const UserReportItem({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    this.phone,
    required this.isActive,
    this.createdAt,
  });
}

class ClientReportItem {
  final String id;
  final String companyName;
  final String? contactName;
  final String? email;
  final String? phone;
  final String status;
  final String? notes;
  final String? createdAt;

  const ClientReportItem({
    required this.id,
    required this.companyName,
    this.contactName,
    this.email,
    this.phone,
    required this.status,
    this.notes,
    this.createdAt,
  });
}

class TeamReportItem {
  final String id;
  final String name;
  final String department;
  final String? leaderName;
  final int memberCount;

  const TeamReportItem({
    required this.id,
    required this.name,
    required this.department,
    this.leaderName,
    required this.memberCount,
  });
}

class EmployeeDossier {
  final UserReportItem user;
  final List<DetailedTaskReportItem> assignedTasks;
  final List<AttendanceReportItem> attendanceLogs;
  final List<PenaltyReportItem> penalties;
  final List<CommentReportItem> comments;

  const EmployeeDossier({
    required this.user,
    required this.assignedTasks,
    required this.attendanceLogs,
    required this.penalties,
    required this.comments,
  });

  double get totalHours => attendanceLogs.fold(0.0, (acc, a) => acc + a.hoursWorked);
  double get totalPenalties => penalties.fold(0.0, (acc, p) => acc + p.amount);
}

class ClientDossier {
  final ClientReportItem client;
  final List<DetailedTaskReportItem> tasks;
  final List<CrmReportItem> crmEntries;
  final List<ClientMeetingReportItem> meetings;
  final List<CommentReportItem> comments;

  const ClientDossier({
    required this.client,
    required this.tasks,
    required this.crmEntries,
    required this.meetings,
    required this.comments,
  });

  double get totalContractValue => crmEntries.fold(0.0, (acc, c) => acc + c.amount);
  double get totalPaid => crmEntries.fold(0.0, (acc, c) => acc + c.paidAmount);
  double get totalOutstanding => totalContractValue - totalPaid;
}

class SuperAdminReportData {
  final String reportPeriodTitle;

  // Directory lists
  final List<UserReportItem> userList;
  final List<ClientReportItem> clientList;
  final List<TeamReportItem> teamList;

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

  // Meetings
  final List<ClientMeetingReportItem> meetingList;

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
    required this.reportPeriodTitle,
    required this.userList,
    required this.clientList,
    required this.teamList,
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
    required this.meetingList,
    required this.totalExpenses,
    required this.totalPenalties,
    required this.expenseList,
    required this.expenseCategories,
    required this.penaltyList,
    required this.totalComments,
    required this.commentsList,
  });

  double get netBalance => totalRevenue - totalExpenses - totalPenalties;

  /// Tasks categorized into Department map
  Map<String, List<DetailedTaskReportItem>> get tasksByDepartment {
    final Map<String, List<DetailedTaskReportItem>> map = {};
    for (final t in taskList) {
      final dept = (t.department != null && t.department!.trim().isNotEmpty)
          ? t.department!
          : 'General';
      map.putIfAbsent(dept, () => []).add(t);
    }
    return map;
  }

  /// Detailed Employee Dossiers for every staff member in userList
  List<EmployeeDossier> get employeeDossiers {
    return userList.map((u) {
      final userTasks = taskList.where((t) {
        return t.assignees.any((a) => a.profileId == u.id);
      }).toList();

      final userAtt = attendanceList.where((a) {
        return a.employeeId == u.id || a.userName.toLowerCase() == u.fullName.toLowerCase();
      }).toList();

      final userPenalties = penaltyList.where((p) {
        return p.employeeId == u.id || p.employeeName.toLowerCase() == u.fullName.toLowerCase();
      }).toList();

      final userComments = commentsList.where((c) {
        return c.authorId == u.id || c.authorName.toLowerCase() == u.fullName.toLowerCase();
      }).toList();

      return EmployeeDossier(
        user: u,
        assignedTasks: userTasks,
        attendanceLogs: userAtt,
        penalties: userPenalties,
        comments: userComments,
      );
    }).toList();
  }

  /// Detailed Client Dossiers for every registered client
  List<ClientDossier> get clientDossiers {
    return clientList.map((c) {
      final clientTasks = taskList.where((t) {
        return (t.clientId != null && t.clientId == c.id) ||
            (t.clientName != null && t.clientName!.toLowerCase() == c.companyName.toLowerCase());
      }).toList();

      final clientCrm = crmList.where((entry) {
        return (entry.clientId != null && entry.clientId == c.id) ||
            (entry.clientName.toLowerCase() == c.companyName.toLowerCase());
      }).toList();

      final clientMeetings = meetingList.where((m) => m.clientId == c.id).toList();

      final taskIds = clientTasks.map((t) => t.id).toSet();
      final clientComments = commentsList.where((cm) => taskIds.contains(cm.taskId)).toList();

      return ClientDossier(
        client: c,
        tasks: clientTasks,
        crmEntries: clientCrm,
        meetings: clientMeetings,
        comments: clientComments,
      );
    }).toList();
  }
}

class SuperAdminReportRepository {
  static final _admin = SupabaseService.adminClient;

  static Future<SuperAdminReportData> fetchMasterReport({
    DateTimeRange? dateRange,
    String filterTitle = 'All Time',
  }) async {
    bool inRange(String? dateStr) {
      if (dateRange == null || dateStr == null || dateStr.trim().isEmpty) return true;
      final dt = DateTime.tryParse(dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr);
      if (dt == null) return true;
      final start = DateTime(dateRange.start.year, dateRange.start.month, dateRange.start.day);
      final end = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59);
      return (dt.isAfter(start) || dt.isAtSameMomentAs(start)) &&
             (dt.isBefore(end) || dt.isAtSameMomentAs(end));
    }

    // 1. User Names map & Teams Mapping & Directory
    final Map<String, String> userNames = {};
    final Map<String, String> teamNames = {};
    final Map<String, String> teamDepts = {};
    final List<TeamReportItem> teamList = [];
    try {
      final teamsData = await _admin
          .from('teams')
          .select('*, leader:profiles!teams_leader_id_fkey(full_name)')
          .order('name', ascending: true);

      for (final tm in teamsData) {
        final id = tm['id'] as String;
        final name = tm['name'] as String? ?? 'Team';
        final dept = tm['department'] as String? ?? 'General';
        teamNames[id] = name;
        teamDepts[id] = dept;

        final leaderObj = tm['leader'] as Map<String, dynamic>?;
        final leaderId = tm['leader_id'] as String?;
        final leaderName = leaderObj?['full_name'] as String? ?? (leaderId != null ? userNames[leaderId] : null);

        int mCount = 0;
        try {
          final mRes = await _admin.from('team_members').select('id').eq('team_id', id);
          mCount = mRes.length;
        } catch (_) {}

        teamList.add(
          TeamReportItem(
            id: id,
            name: name,
            department: dept,
            leaderName: leaderName,
            memberCount: mCount,
          ),
        );
      }
    } catch (_) {}

    // 2. Profiles Mapping & Users Directory (Safe Query without non-existent columns)
    final List<UserReportItem> userList = [];
    try {
      List<dynamic> profilesData = [];
      try {
        profilesData = await _admin
            .from('profiles')
            .select('id, full_name, phone, role, status, team_id, created_at, team:teams(name, department)')
            .order('full_name', ascending: true);
      } catch (_) {
        profilesData = await _admin
            .from('profiles')
            .select('id, full_name, phone, role, status, team_id, created_at')
            .order('full_name', ascending: true);
      }

      for (final p in profilesData) {
        final id = p['id'] as String;
        final name = p['full_name'] as String? ?? 'Unknown User';
        userNames[id] = name;

        final teamObj = p['team'] is Map ? (p['team'] as Map) : null;
        final teamId = p['team_id'] as String?;
        final dept = teamObj?['department'] as String? ?? (teamId != null ? (teamDepts[teamId] ?? 'General') : 'General');
        final st = (p['status'] as String? ?? 'active').toLowerCase();

        userList.add(
          UserReportItem(
            id: id,
            fullName: name,
            email: p['email'] as String? ?? '',
            role: (p['role'] as String? ?? 'employee').toLowerCase(),
            department: dept,
            phone: p['phone'] as String?,
            isActive: st == 'active',
            createdAt: p['created_at'] as String?,
          ),
        );
      }
    } catch (_) {}

    // 3. Clients Directory (Safe select *)
    final List<ClientReportItem> clientList = [];
    try {
      final clientData = await _admin
          .from('client_profiles')
          .select('*')
          .order('company_name', ascending: true);

      for (final c in clientData) {
        final cid = c['id'] as String? ?? '';
        final cName = c['company_name'] as String? ?? 'Client';
        if (cid.isNotEmpty) {
          userNames[cid] = cName;
        }

        clientList.add(
          ClientReportItem(
            id: cid,
            companyName: cName,
            contactName: (c['contact_person'] ?? c['contact_name']) as String?,
            email: c['email'] as String?,
            phone: c['phone'] as String?,
            status: c['status'] as String? ?? 'active',
            notes: c['notes'] as String?,
            createdAt: c['created_at'] as String?,
          ),
        );
      }
    } catch (_) {}

    // 4. Task Comments Query (Safe select * and author_id mapping)
    List<dynamic> commentsData = [];
    try {
      commentsData = await _admin
          .from('task_comments')
          .select('*')
          .order('created_at', ascending: false);
    } catch (_) {}

    // 5. Tasks Query
    List<dynamic> tasksData = [];
    try {
      tasksData = await _admin
          .from('tasks')
          .select('*, client:client_profiles(company_name), team:teams(name, department), creator:profiles!tasks_created_by_fkey(full_name), task_assignees(profile_id, is_lead)')
          .order('created_at', ascending: false);
    } catch (_) {
      try {
        tasksData = await _admin.from('tasks').select('*').order('created_at', ascending: false);
      } catch (_) {}
    }

    final Map<String, String> taskTitles = {};
    for (final t in tasksData) {
      final id = t['id'] as String?;
      if (id != null) {
        taskTitles[id] = t['title'] as String? ?? 'Untitled Task';
      }
    }

    final List<CommentReportItem> commentItems = [];
    for (final c in commentsData) {
      final cDate = c['created_at'] as String? ?? '';
      if (!inRange(cDate)) continue;

      final tid = c['task_id'] as String? ?? '';
      final uid = (c['author_id'] ?? c['user_id'] ?? c['profile_id']) as String? ?? '';
      final author = userNames[uid] ?? 'User';
      final title = taskTitles[tid] ?? 'Task';

      commentItems.add(
        CommentReportItem(
          id: c['id'] as String? ?? '',
          taskId: tid,
          authorId: uid,
          authorName: author,
          taskTitle: title,
          content: c['content'] as String? ?? '',
          createdAt: cDate,
        ),
      );
    }

    final Map<String, int> tasksByStatus = {};
    final Map<String, int> tasksByPriority = {};
    final List<DetailedTaskReportItem> taskList = [];

    for (final t in tasksData) {
      final cDate = (t['created_at'] ?? t['due_date'] ?? t['start_date']) as String?;
      if (!inRange(cDate)) continue;

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
      final clientId = t['client_id'] as String?;
      final clientName = clientObj?['company_name'] as String?;

      final creatorObj = t['creator'] as Map<String, dynamic>?;
      final creatorId = t['created_by'] as String?;
      final creatorName = creatorObj?['full_name'] as String? ?? (creatorId != null ? userNames[creatorId] : null);

      final List<TaskAssigneeInfo> assignees = [];
      final Set<String> currentIds = {};

      final rawAssignees = t['task_assignees'] as List?;
      if (rawAssignees != null) {
        for (final a in rawAssignees) {
          final pid = a['profile_id'] as String?;
          if (pid != null && userNames[pid] != null) {
            currentIds.add(pid);
            assignees.add(
              TaskAssigneeInfo(
                profileId: pid,
                name: userNames[pid]!,
                isLead: a['is_lead'] as bool? ?? false,
              ),
            );
          }
        }
      }

      final directAssigneeId = (t['assigned_to'] ?? t['assignee_id'] ?? t['employee_id']) as String?;
      if (directAssigneeId != null && userNames[directAssigneeId] != null) {
        if (!currentIds.contains(directAssigneeId)) {
          currentIds.add(directAssigneeId);
          assignees.add(TaskAssigneeInfo(profileId: directAssigneeId, name: userNames[directAssigneeId]!, isLead: false));
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
          clientId: clientId,
          teamName: teamName,
          department: dept,
          createdByName: creatorName,
          startDate: t['start_date'] as String?,
          dueDate: t['due_date'] as String?,
          createdAt: t['created_at'] as String?,
          updatedAt: t['updated_at'] as String?,
          attachmentUrl: t['attachment_url'] as String?,
          assignees: assignees,
          comments: taskComments,
        ),
      );
    }

    // 6. Attendance Records Query
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
        final aDate = (a['attendance_date'] ?? a['date']) as String? ?? '';
        if (!inRange(aDate)) continue;

        final empMap = a['employee'] as Map<String, dynamic>?;
        final empId = a['employee_id'] as String? ?? '';
        final empName = empMap?['full_name'] as String? ?? (empId.isNotEmpty ? (userNames[empId] ?? 'Employee') : 'Employee');
        final st = (a['status'] as String? ?? 'present').toLowerCase();

        if (st == 'present') {
          present++;
        } else if (st == 'late') {
          late++;
        } else if (st == 'absent') {
          absent++;
        }

        final hrs = (a['hours_worked'] as num?)?.toDouble() ?? (a['total_hours'] as num?)?.toDouble() ?? 0.0;
        hoursWorkedSum += hrs;

        attendanceList.add(
          AttendanceReportItem(
            id: a['id'] as String? ?? '',
            employeeId: empId,
            userName: empName,
            date: aDate,
            checkIn: a['check_in_time'] as String?,
            checkOut: a['check_out_time'] as String?,
            status: st,
            hoursWorked: hrs,
            isManual: a['is_manual_override'] as bool? ?? a['is_manual'] as bool? ?? false,
            dailyReport: a['daily_report'] as String?,
            notes: a['notes'] as String?,
            wifiSsid: a['wifi_ssid'] as String?,
          ),
        );
      }
    } catch (_) {}

    // 7. Finance / CRM Query
    List<CrmReportItem> crmList = [];
    double revenueSum = 0.0;
    double paidRevenueSum = 0.0;

    try {
      final crmData = await _admin
          .from('crm_entries')
          .select('*, client:client_profiles(company_name)')
          .order('created_at', ascending: false);

      for (final c in crmData) {
        final cDate = (c['created_at'] ?? c['payment_date'] ?? c['due_date']) as String?;
        if (!inRange(cDate)) continue;

        final clientMap = c['client'] as Map<String, dynamic>?;
        final clientId = c['client_id'] as String?;
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
            clientId: clientId,
            amount: amt,
            paidAmount: paid,
            status: c['status'] as String? ?? 'unpaid',
            sourceType: c['source_type'] as String? ?? 'manual',
            dueDate: c['due_date'] as String?,
            paymentDate: c['payment_date'] as String?,
            invoiceNumber: c['invoice_number'] as String?,
            notes: (c['notes'] ?? c['description']) as String?,
            createdAt: c['created_at'] as String?,
          ),
        );
      }
    } catch (_) {}

    // 8. Client Meetings / Events Query
    List<ClientMeetingReportItem> meetingList = [];
    try {
      final eventsData = await _admin
          .from('events')
          .select('id, title, description, start_time, end_time, location, client_id, meeting_notes, status, created_at')
          .order('start_time', ascending: false);

      for (final e in eventsData) {
        final stDate = e['start_time'] as String?;
        if (!inRange(stDate)) continue;
        final cid = e['client_id'] as String?;
        if (cid == null || cid.isEmpty) continue;

        meetingList.add(
          ClientMeetingReportItem(
            id: e['id'] as String? ?? '',
            clientId: cid,
            title: e['title'] as String? ?? 'Meeting',
            description: e['description'] as String?,
            startTime: stDate ?? '',
            endTime: e['end_time'] as String? ?? '',
            location: e['location'] as String?,
            meetingNotes: e['meeting_notes'] as String?,
            status: e['status'] as String? ?? 'scheduled',
          ),
        );
      }
    } catch (_) {}

    // 9. Expenses Query
    List<DetailedExpenseItem> expenseList = [];
    double expenseSum = 0.0;
    final Map<String, _CatAcc> catMap = {};

    try {
      final expData = await _admin
          .from('expenses')
          .select('*, category:expense_categories(name), recorder:profiles!expenses_recorded_by_fkey(full_name)')
          .order('expense_date', ascending: false);

      for (final e in expData) {
        final eDate = (e['expense_date'] ?? e['created_at']) as String? ?? '';
        if (!inRange(eDate)) continue;

        final amt = (e['amount'] as num?)?.toDouble() ?? 0.0;
        expenseSum += amt;

        final catObj = e['category'] is Map ? (e['category'] as Map) : null;
        final catName = catObj?['name'] as String? ?? (e['category'] is String ? e['category'] as String : 'General');
        catMap.putIfAbsent(catName, () => _CatAcc()).add(amt);

        final recorderObj = e['recorder'] is Map ? (e['recorder'] as Map) : null;
        final recId = e['recorded_by'] as String?;
        final recorderName = recorderObj?['full_name'] as String? ?? (recId != null ? (userNames[recId] ?? 'User') : 'User');

        expenseList.add(
          DetailedExpenseItem(
            id: e['id'] as String? ?? '',
            categoryName: catName,
            amount: amt,
            date: eDate,
            description: e['description'] as String? ?? '',
            recordedByName: recorderName,
            status: e['status'] as String? ?? 'approved',
            receiptUrl: e['receipt_url'] as String?,
            createdAt: e['created_at'] as String?,
          ),
        );
      }
    } catch (_) {}

    final List<ExpenseCategoryReportItem> expenseCategories = catMap.entries.map((e) {
      return ExpenseCategoryReportItem(
        categoryName: e.key,
        totalAmount: e.value.total,
        count: e.value.count,
      );
    }).toList();

    // 10. Penalties Query
    List<PenaltyReportItem> penaltyList = [];
    double penaltiesSum = 0.0;
    try {
      final penData = await _admin
          .from('penalties')
          .select('*, employee:profiles!penalties_employee_id_fkey(full_name)')
          .order('issue_date', ascending: false);

      for (final p in penData) {
        final pDate = (p['issue_date'] ?? p['created_at']) as String? ?? '';
        if (!inRange(pDate)) continue;

        final amt = (p['amount'] as num?)?.toDouble() ?? 0.0;
        penaltiesSum += amt;

        final empObj = p['employee'] as Map<String, dynamic>?;
        final empId = p['employee_id'] as String? ?? '';
        final empName = empObj?['full_name'] as String? ?? (empId.isNotEmpty ? (userNames[empId] ?? 'Employee') : 'Employee');

        penaltyList.add(
          PenaltyReportItem(
            id: p['id'] as String? ?? '',
            employeeId: empId,
            employeeName: empName,
            amount: amt,
            reason: p['reason'] as String? ?? 'Penalty',
            date: pDate,
            status: p['status'] as String? ?? 'active',
            notes: p['notes'] as String?,
            createdAt: p['created_at'] as String?,
          ),
        );
      }
    } catch (_) {}

    return SuperAdminReportData(
      reportPeriodTitle: filterTitle,
      userList: userList,
      clientList: clientList,
      teamList: teamList,
      totalTasks: taskList.length,
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
      meetingList: meetingList,
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
