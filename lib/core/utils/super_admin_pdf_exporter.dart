// lib/core/utils/super_admin_pdf_exporter.dart
// Generates and prints/exports an un-truncated multi-page PDF report for Super Admin.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../repositories/super_admin_report_repository.dart';

class SuperAdminPdfExporter {
  /// Generates the complete PDF document without truncation and opens the print / save-as-PDF dialog.
  static Future<void> exportAndPrintPdf(SuperAdminReportData data) async {
    final pdf = pw.Document();

    final primaryColor = PdfColors.indigo900;
    final goldColor = PdfColors.amber800;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 1)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'TASK ORA - SUPER ADMIN MASTER REPORT',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.Text(
                    'Generated on ${DateTime.now().toString().split('.')[0]}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 10),

          // Executive Summary
          pw.Text('EXECUTIVE SUMMARY', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: goldColor)),
          pw.SizedBox(height: 6),
          pw.GridView(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.8,
            children: [
              _kpiBox('Total Tasks', '${data.totalTasks}', PdfColors.blue50),
              _kpiBox('Hours Logged', '${data.totalHoursWorked.toStringAsFixed(1)} h', PdfColors.purple50),
              _kpiBox('Net Balance', '\$${data.netBalance.toStringAsFixed(2)}', data.netBalance >= 0 ? PdfColors.green50 : PdfColors.red50),
              _kpiBox('Total Revenue', '\$${data.totalRevenue.toStringAsFixed(2)}', PdfColors.green50),
              _kpiBox('Total Expenses', '\$${data.totalExpenses.toStringAsFixed(2)}', PdfColors.orange50),
              _kpiBox('Total Penalties', '\$${data.totalPenalties.toStringAsFixed(2)}', PdfColors.amber50),
            ],
          ),
          pw.SizedBox(height: 16),

          // 1. Detailed Tasks & Employees Section
          pw.Text('1. DETAILED TASKS & ASSIGNED EMPLOYEES (${data.taskList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          data.taskList.isEmpty
              ? pw.Text('No tasks recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
              : pw.Column(
                  children: data.taskList.map((t) {
                    final assigneesStr = t.assignees.isNotEmpty
                        ? t.assignees.map((a) => '${a.name}${a.isLead ? " (Lead)" : ""}').join(', ')
                        : 'None';
                    final clientDept = [
                      if (t.clientName != null) 'Client: ${t.clientName}',
                      if (t.teamName != null) 'Team: ${t.teamName}',
                      if (t.department != null) 'Dept: ${t.department}',
                    ].join(' | ');

                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: PdfColors.grey50,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(t.title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                              pw.Text('[${t.priority.toUpperCase()}]  ${t.status.toUpperCase()} (${t.completionPercentage}%)',
                                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: goldColor)),
                            ],
                          ),
                          if (t.description != null && t.description!.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(t.description!, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
                          ],
                          pw.SizedBox(height: 4),
                          pw.Text(clientDept.isNotEmpty ? clientDept : 'Internal Task', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                          pw.SizedBox(height: 2),
                          pw.Text('Assigned Employees: $assigneesStr', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
                          if (t.cost != null) pw.Text('Cost: \$${t.cost!.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green900)),
                          if (t.comments.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text('Comments (${t.comments.length}):', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                            ...t.comments.map((c) => pw.Text('  • ${c.authorName}: "${c.content}"', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey800))),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
          pw.SizedBox(height: 16),

          // 2. Attendance Logs Section (un-truncated)
          pw.Text('2. ATTENDANCE & LOGS OVERVIEW (${data.attendanceList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          pw.Text('Present: ${data.presentCount}  |  Late: ${data.lateCount}  |  Absent: ${data.absentCount}  |  Total Work Hours: ${data.totalHoursWorked.toStringAsFixed(1)} h',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800)),
          pw.SizedBox(height: 6),
          data.attendanceList.isEmpty
              ? pw.Text('No attendance logs recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headers: ['Employee Name', 'Date', 'Check In', 'Check Out', 'Hours', 'Status', 'Override'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7),
                  data: data.attendanceList.map((a) => [
                    a.userName,
                    a.date,
                    a.checkIn ?? '-',
                    a.checkOut ?? '-',
                    '${a.hoursWorked.toStringAsFixed(1)} h',
                    a.status.toUpperCase(),
                    a.isManual ? 'Manual Override' : 'Auto / WiFi',
                  ]).toList(),
                ),
          pw.SizedBox(height: 16),

          // 3. CRM & Finance Transactions
          pw.Text('3. CRM & FINANCIAL TRANSACTIONS (${data.crmList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          data.crmList.isEmpty
              ? pw.Text('No financial transactions recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headers: ['Title', 'Client Name', 'Billed Amount', 'Paid Amount', 'Outstanding', 'Status'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7),
                  data: data.crmList.map((c) => [
                    c.title,
                    c.clientName,
                    '\$${c.amount.toStringAsFixed(2)}',
                    '\$${c.paidAmount.toStringAsFixed(2)}',
                    '\$${c.outstanding.toStringAsFixed(2)}',
                    c.status.toUpperCase(),
                  ]).toList(),
                ),
          pw.SizedBox(height: 16),

          // 4. Expense Entries
          pw.Text('4. EXPENSE ENTRIES (${data.expenseList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          data.expenseList.isEmpty
              ? pw.Text('No expense entries recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headers: ['Category', 'Description', 'Amount', 'Date', 'Recorded By', 'Status'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7),
                  data: data.expenseList.map((e) => [
                    e.categoryName,
                    e.description.isNotEmpty ? e.description : '-',
                    '\$${e.amount.toStringAsFixed(2)}',
                    e.date,
                    e.recordedByName,
                    e.status.toUpperCase(),
                  ]).toList(),
                ),
          pw.SizedBox(height: 16),

          // 5. Penalties
          if (data.penaltyList.isNotEmpty) ...[
            pw.Text('5. PENALTIES LOG (${data.penaltyList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Employee Name', 'Reason', 'Amount', 'Date', 'Status'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
              headerDecoration: pw.BoxDecoration(color: primaryColor),
              cellStyle: const pw.TextStyle(fontSize: 7),
              data: data.penaltyList.map((p) => [
                p.employeeName,
                p.reason,
                '\$${p.amount.toStringAsFixed(2)}',
                p.date,
                p.status.toUpperCase(),
              ]).toList(),
            ),
            pw.SizedBox(height: 16),
          ],

          // 6. Comments Feed
          pw.Text('6. TASK COMMENTS LOG (${data.commentsList.length})', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: primaryColor)),
          pw.SizedBox(height: 6),
          data.commentsList.isEmpty
              ? pw.Text('No task comments recorded.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
              : pw.TableHelper.fromTextArray(
                  headers: ['Author Name', 'Task Reference', 'Comment Content', 'Date'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7),
                  data: data.commentsList.map((c) => [
                    c.authorName,
                    c.taskTitle,
                    c.content,
                    c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt,
                  ]).toList(),
                ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SuperAdmin_MasterReport_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _kpiBox(String title, String value, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        ],
      ),
    );
  }
}
