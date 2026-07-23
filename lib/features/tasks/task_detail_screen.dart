// lib/features/tasks/task_detail_screen.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'task_detail_sheet.dart';

class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Edit Task')),
      body: TaskDetailSheet(taskId: taskId),
    );
  }
}
