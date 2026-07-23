// lib/core/data/mock_data.dart
// All static mock data for CB TO-DO UI

class MockTask {
  final String id, title, assignee, priority, status, dueDate, tag;
  final int progress;
  const MockTask({
    required this.id,
    required this.title,
    required this.assignee,
    required this.priority,
    required this.status,
    required this.dueDate,
    required this.tag,
    required this.progress,
  });
}

class MockUser {
  final String id, name, email, role, status, joinDate;
  const MockUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.joinDate,
  });
}

class MockExpense {
  final String id, title, category, date;
  final double amount;
  const MockExpense({
    required this.id,
    required this.title,
    required this.category,
    required this.date,
    required this.amount,
  });
}

class MockNotification {
  final String id, title, body, time, type;
  final bool read;
  const MockNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    required this.read,
  });
}

class MockPenalty {
  final String id, employee, type, reason, date, status;
  final double amount;
  const MockPenalty({
    required this.id,
    required this.employee,
    required this.type,
    required this.reason,
    required this.date,
    required this.status,
    required this.amount,
  });
}

class MockData {
  MockData._();

  // ── Tasks ──────────────────────────────────────────────────────────────────
  static const List<MockTask> tasks = [
    MockTask(
      id: 't1',
      title: 'Redesign onboarding flow',
      assignee: 'Sara Ahmed',
      priority: 'High',
      status: 'In Progress',
      dueDate: 'May 15',
      tag: 'Design',
      progress: 65,
    ),
    MockTask(
      id: 't2',
      title: 'API rate-limit implementation',
      assignee: 'Omar Khalid',
      priority: 'High',
      status: 'In Progress',
      dueDate: 'May 16',
      tag: 'Backend',
      progress: 40,
    ),
    MockTask(
      id: 't3',
      title: 'Q2 performance review',
      assignee: 'Lina Hassan',
      priority: 'Medium',
      status: 'To Do',
      dueDate: 'May 20',
      tag: 'HR',
      progress: 0,
    ),
    MockTask(
      id: 't4',
      title: 'Write unit tests for auth module',
      assignee: 'Yusuf Ali',
      priority: 'Medium',
      status: 'To Do',
      dueDate: 'May 22',
      tag: 'QA',
      progress: 0,
    ),
    MockTask(
      id: 't5',
      title: 'Deploy v2.3 to production',
      assignee: 'Sara Ahmed',
      priority: 'High',
      status: 'Done',
      dueDate: 'May 10',
      tag: 'DevOps',
      progress: 100,
    ),
    MockTask(
      id: 't6',
      title: 'Monthly finance report',
      assignee: 'Lina Hassan',
      priority: 'Medium',
      status: 'Done',
      dueDate: 'May 08',
      tag: 'Finance',
      progress: 100,
    ),
    MockTask(
      id: 't7',
      title: 'Update mobile push notifications',
      assignee: 'Omar Khalid',
      priority: 'Low',
      status: 'To Do',
      dueDate: 'May 28',
      tag: 'Mobile',
      progress: 0,
    ),
    MockTask(
      id: 't8',
      title: 'Security audit Phase 1',
      assignee: 'Yusuf Ali',
      priority: 'High',
      status: 'In Progress',
      dueDate: 'May 18',
      tag: 'Security',
      progress: 30,
    ),
    MockTask(
      id: 't9',
      title: 'Localisation for Arabic UI',
      assignee: 'Sara Ahmed',
      priority: 'Low',
      status: 'To Do',
      dueDate: 'Jun 01',
      tag: 'Design',
      progress: 0,
    ),
    MockTask(
      id: 't10',
      title: 'Database index optimisation',
      assignee: 'Omar Khalid',
      priority: 'Medium',
      status: 'Done',
      dueDate: 'May 09',
      tag: 'Backend',
      progress: 100,
    ),
  ];

  static List<MockTask> get todoTasks =>
      tasks.where((t) => t.status == 'To Do').toList();
  static List<MockTask> get inProgressTasks =>
      tasks.where((t) => t.status == 'In Progress').toList();
  static List<MockTask> get doneTasks =>
      tasks.where((t) => t.status == 'Done').toList();

  // ── Users ──────────────────────────────────────────────────────────────────
  static const List<MockUser> users = [
    MockUser(
      id: 'u1',
      name: 'Sara Ahmed',
      email: 'sara@cbtodo.com',
      role: 'Admin',
      status: 'Active',
      joinDate: 'Jan 2024',
    ),
    MockUser(
      id: 'u2',
      name: 'Omar Khalid',
      email: 'omar@cbtodo.com',
      role: 'Developer',
      status: 'Active',
      joinDate: 'Mar 2024',
    ),
    MockUser(
      id: 'u3',
      name: 'Lina Hassan',
      email: 'lina@cbtodo.com',
      role: 'Manager',
      status: 'Active',
      joinDate: 'Feb 2024',
    ),
    MockUser(
      id: 'u4',
      name: 'Yusuf Ali',
      email: 'yusuf@cbtodo.com',
      role: 'QA Engineer',
      status: 'Active',
      joinDate: 'Apr 2024',
    ),
    MockUser(
      id: 'u5',
      name: 'Nadia Farouk',
      email: 'nadia@cbtodo.com',
      role: 'Designer',
      status: 'Inactive',
      joinDate: 'Jun 2023',
    ),
    MockUser(
      id: 'u6',
      name: 'Khaled Mansour',
      email: 'khaled@cbtodo.com',
      role: 'Developer',
      status: 'Active',
      joinDate: 'May 2024',
    ),
  ];

  // ── Expenses ───────────────────────────────────────────────────────────────
  static const List<MockExpense> expenses = [
    MockExpense(
      id: 'e1',
      title: 'Team lunch',
      category: 'Food',
      date: 'May 12',
      amount: 185.0,
    ),
    MockExpense(
      id: 'e2',
      title: 'AWS hosting',
      category: 'Infrastructure',
      date: 'May 11',
      amount: 540.0,
    ),
    MockExpense(
      id: 'e3',
      title: 'Design software licence',
      category: 'Software',
      date: 'May 10',
      amount: 99.0,
    ),
    MockExpense(
      id: 'e4',
      title: 'Office supplies',
      category: 'Office',
      date: 'May 09',
      amount: 64.0,
    ),
    MockExpense(
      id: 'e5',
      title: 'Taxi to client meeting',
      category: 'Transport',
      date: 'May 08',
      amount: 32.0,
    ),
    MockExpense(
      id: 'e6',
      title: 'Conference tickets',
      category: 'Training',
      date: 'May 07',
      amount: 450.0,
    ),
    MockExpense(
      id: 'e7',
      title: 'Printer paper',
      category: 'Office',
      date: 'May 06',
      amount: 22.0,
    ),
    MockExpense(
      id: 'e8',
      title: 'Zoom subscription',
      category: 'Software',
      date: 'May 05',
      amount: 49.0,
    ),
  ];

  // ── Notifications ──────────────────────────────────────────────────────────
  static const List<MockNotification> notifications = [
    MockNotification(
      id: 'n1',
      title: 'Task assigned to you',
      body: 'Omar assigned "Security audit Phase 1" to you.',
      time: '2m ago',
      type: 'task',
      read: false,
    ),
    MockNotification(
      id: 'n2',
      title: 'Task completed',
      body: 'Sara completed "Deploy v2.3 to production".',
      time: '1h ago',
      type: 'done',
      read: false,
    ),
    MockNotification(
      id: 'n3',
      title: 'Penalty issued',
      body: 'A late-arrival penalty was applied to Nadia Farouk.',
      time: '3h ago',
      type: 'penalty',
      read: false,
    ),
    MockNotification(
      id: 'n4',
      title: 'New user registered',
      body: 'Khaled Mansour joined the team as a Developer.',
      time: 'Yesterday',
      type: 'user',
      read: true,
    ),
    MockNotification(
      id: 'n5',
      title: 'Monthly report ready',
      body: 'The May finance report is available for review.',
      time: '2 days ago',
      type: 'finance',
      read: true,
    ),
    MockNotification(
      id: 'n6',
      title: 'Leave request',
      body: 'Yusuf Ali requested annual leave from May 20–24.',
      time: '3 days ago',
      type: 'hr',
      read: true,
    ),
    MockNotification(
      id: 'n7',
      title: 'System maintenance',
      body: 'Scheduled downtime on May 14 at 2 AM.',
      time: '4 days ago',
      type: 'system',
      read: true,
    ),
  ];

  // ── Penalties ──────────────────────────────────────────────────────────────
  static const List<MockPenalty> penalties = [
    MockPenalty(
      id: 'p1',
      employee: 'Nadia Farouk',
      type: 'Late Arrival',
      reason: 'Late > 30 min on 3 days',
      date: 'May 10',
      status: 'Active',
      amount: 50.0,
    ),
    MockPenalty(
      id: 'p2',
      employee: 'Khaled Mansour',
      type: 'Absence',
      reason: 'Unexcused absence',
      date: 'May 08',
      status: 'Active',
      amount: 100.0,
    ),
    MockPenalty(
      id: 'p3',
      employee: 'Omar Khalid',
      type: 'Policy Violation',
      reason: 'Skipped daily standup',
      date: 'May 06',
      status: 'Resolved',
      amount: 25.0,
    ),
    MockPenalty(
      id: 'p4',
      employee: 'Nadia Farouk',
      type: 'Late Arrival',
      reason: 'Late > 15 min',
      date: 'Apr 28',
      status: 'Resolved',
      amount: 25.0,
    ),
    MockPenalty(
      id: 'p5',
      employee: 'Yusuf Ali',
      type: 'Absence',
      reason: 'Unexcused half-day',
      date: 'Apr 22',
      status: 'Resolved',
      amount: 50.0,
    ),
  ];

  // ── Finance ────────────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> monthlyRevenue = [
    {'month': 'Nov', 'value': 32000.0},
    {'month': 'Dec', 'value': 41000.0},
    {'month': 'Jan', 'value': 28000.0},
    {'month': 'Feb', 'value': 35000.0},
    {'month': 'Mar', 'value': 47000.0},
    {'month': 'Apr', 'value': 52000.0},
    {'month': 'May', 'value': 61000.0},
  ];

  static const List<Map<String, dynamic>> expenseCategories = [
    {'label': 'Infrastructure', 'value': 35.0},
    {'label': 'Software', 'value': 22.0},
    {'label': 'Salaries', 'value': 30.0},
    {'label': 'Other', 'value': 13.0},
  ];

  // ── Attendance ─────────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> attendanceSummary = [
    {'name': 'Sara Ahmed', 'present': 22, 'absent': 0, 'late': 1, 'pct': 96},
    {'name': 'Omar Khalid', 'present': 20, 'absent': 1, 'late': 2, 'pct': 87},
    {'name': 'Lina Hassan', 'present': 23, 'absent': 0, 'late': 0, 'pct': 100},
    {'name': 'Yusuf Ali', 'present': 19, 'absent': 2, 'late': 2, 'pct': 83},
    {
      'name': 'Khaled Mansour',
      'present': 21,
      'absent': 1,
      'late': 1,
      'pct': 91,
    },
  ];

  // ── Roles ──────────────────────────────────────────────────────────────────
  static const List<Map<String, dynamic>> roles = [
    {'name': 'Admin', 'count': 1, 'color': 0xFF000000},
    {'name': 'Manager', 'count': 2, 'color': 0xFF755B00},
    {'name': 'Developer', 'count': 8, 'color': 0xFF1565C0},
    {'name': 'Designer', 'count': 3, 'color': 0xFF880E4F},
    {'name': 'QA Engineer', 'count': 2, 'color': 0xFF004D40},
    {'name': 'Finance', 'count': 1, 'color': 0xFF4A148C},
  ];

  static const List<String> permissions = [
    'View Dashboard',
    'Manage Tasks',
    'View Reports',
    'Manage Users',
    'Manage Roles',
    'Finance Access',
    'Issue Penalties',
    'System Settings',
    'Export Data',
    'Delete Records',
  ];
}
