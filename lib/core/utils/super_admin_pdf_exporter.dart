// lib/core/utils/super_admin_pdf_exporter.dart
// Generates and prints/exports a beautifully structured, unicode-safe A4 PDF report for Super Admin.

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../repositories/super_admin_report_repository.dart';

class SuperAdminPdfExporter {
  /// Sanitize text strings to avoid character encoding crashes with default PDF fonts.
  static String _c(String? text) {
    if (text == null || text.isEmpty) return '';
    return text
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '*')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
  }

  /// Generates the complete A4 PDF document with Unicode font support and dual layout/share fallback.
  static Future<void> exportAndPrintPdf(SuperAdminReportData data) async {
    pw.Font? fontBase;
    pw.Font? fontBold;

    try {
      fontBase = await PdfGoogleFonts.robotoRegular();
      fontBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      // Fallback if offline or network font request fails
    }

    final pdf = pw.Document(
      theme: (fontBase != null && fontBold != null)
          ? pw.ThemeData.withFont(base: fontBase, bold: fontBold)
          : null,
    );

    const primaryColor = PdfColor.fromInt(0xFF1E293B); // Slate dark navy
    const secondaryColor = PdfColor.fromInt(0xFF0F172A); // Midnight blue
    const goldColor = PdfColor.fromInt(0xFFC9A84C); // Elegant gold
    const lightGreyBg = PdfColor.fromInt(0xFFF8FAFC);
    const borderGrey = PdfColor.fromInt(0xFFE2E8F0);
    const textDark = PdfColor.fromInt(0xFF0F172A);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),

        // Page Header
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: goldColor, width: 1.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const pw.BoxDecoration(
                      color: primaryColor,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Text(
                      'TASK ORA',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SUPER ADMIN MASTER OPERATIONS REPORT',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.Text(
                        'Period: ${_c(data.reportPeriodTitle)}',
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: goldColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
              ),
            ],
          ),
        ),

        // Page Footer
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: borderGrey, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Confidential - TaskOra Operations Management System',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
              ),
              pw.Text(
                'Generated: ${_c(DateTime.now().toString().split('.')[0])}',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
              ),
            ],
          ),
        ),

        // Content Build
        build: (context) => [
          // Executive Summary Banner & KPI Cards
          _sectionHeader('EXECUTIVE SUMMARY & SYSTEM KPI OVERVIEW (${_c(data.reportPeriodTitle)})', primaryColor, goldColor),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _kpiBox('Total Tasks', '${data.totalTasks}', const PdfColor.fromInt(0xFFEFF6FF), primaryColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Hours Logged', '${data.totalHoursWorked.toStringAsFixed(1)} h', const PdfColor.fromInt(0xFFF3E8FF), primaryColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Net Balance', '\$${data.netBalance.toStringAsFixed(2)}', data.netBalance >= 0 ? const PdfColor.fromInt(0xFFF0FDF4) : const PdfColor.fromInt(0xFFFEF2F2), data.netBalance >= 0 ? PdfColors.green800 : PdfColors.red800)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _kpiBox('Total Revenue', '\$${data.totalRevenue.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFF0FDF4), PdfColors.green800)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Paid Revenue', '\$${data.totalPaidRevenue.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFECFDF5), PdfColors.green900)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Total Expenses', '\$${data.totalExpenses.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFFFF7ED), PdfColors.orange800)),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(child: _kpiBox('Total Penalties', '\$${data.totalPenalties.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFFEFCE8), goldColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Active Staff Members', '${data.userList.length}', const PdfColor.fromInt(0xFFECFEFF), primaryColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Registered Clients', '${data.clientList.length}', const PdfColor.fromInt(0xFFF0FDFA), primaryColor)),
            ],
          ),
          pw.SizedBox(height: 20),

          // 1. Staff & Employees Master Directory
          _sectionHeader('1. STAFF & EMPLOYEES DIRECTORY (${data.userList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.userList.isEmpty
              ? _emptyText('No user profiles registered.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Full Name', 'Email Address', 'Role', 'Department', 'Phone', 'Status'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 8, color: textDark),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.0),
                    1: pw.FlexColumnWidth(2.5),
                    2: pw.FlexColumnWidth(1.2),
                    3: pw.FlexColumnWidth(1.5),
                    4: pw.FlexColumnWidth(1.5),
                    5: pw.FlexColumnWidth(1.0),
                  },
                  data: data.userList.map((u) => [
                    _c(u.fullName),
                    _c(u.email.isNotEmpty ? u.email : '-'),
                    _c(u.role.toUpperCase()),
                    _c(u.department),
                    _c(u.phone ?? '-'),
                    u.isActive ? 'Active' : 'Inactive',
                  ]).toList(),
                ),
          pw.SizedBox(height: 20),

          // 2. Clients Directory
          if (data.clientList.isNotEmpty) ...[
            _sectionHeader('2. CLIENTS DIRECTORY (${data.clientList.length})', primaryColor, goldColor),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Company Name', 'Contact Person', 'Email Address', 'Phone Number', 'Status', 'Notes'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
              headerDecoration: const pw.BoxDecoration(color: primaryColor),
              cellStyle: const pw.TextStyle(fontSize: 8, color: textDark),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1.8),
                2: pw.FlexColumnWidth(2.2),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(1.0),
                5: pw.FlexColumnWidth(1.4),
              },
              data: data.clientList.map((c) => [
                _c(c.companyName),
                _c(c.contactName ?? '-'),
                _c(c.email ?? '-'),
                _c(c.phone ?? '-'),
                _c(c.status.toUpperCase()),
                _c(c.notes ?? '-'),
              ]).toList(),
            ),
            pw.SizedBox(height: 20),
          ],

          // 3. Detailed Tasks & Assigned Employees Section
          _sectionHeader('3. DETAILED TASKS & ASSIGNED EMPLOYEES (${data.taskList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.taskList.isEmpty
              ? _emptyText('No tasks recorded in system.')
              : pw.Column(
                  children: data.taskList.map((t) {
                    final assigneesStr = t.assignees.isNotEmpty
                        ? t.assignees.map((a) => '${_c(a.name)}${a.isLead ? " [Lead]" : ""}').join(', ')
                        : 'Unassigned';

                    final metaInfo = [
                      if (t.clientName != null) 'Client: ${_c(t.clientName)}',
                      if (t.teamName != null) 'Team: ${_c(t.teamName)}',
                      if (t.department != null) 'Dept: ${_c(t.department)}',
                      if (t.createdByName != null) 'Creator: ${_c(t.createdByName)}',
                      if (t.startDate != null) 'Start: ${_c(t.startDate!.length >= 10 ? t.startDate!.substring(0, 10) : t.startDate)}',
                      if (t.dueDate != null) 'Due: ${_c(t.dueDate!.length >= 10 ? t.dueDate!.substring(0, 10) : t.dueDate)}',
                      if (t.cost != null) 'Cost: \$${t.cost!.toStringAsFixed(2)}',
                    ].join('   |   ');

                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: borderGrey, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: lightGreyBg,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Expanded(
                                child: pw.Text(
                                  _c(t.title),
                                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                                ),
                              ),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: const pw.BoxDecoration(
                                  color: primaryColor,
                                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                                ),
                                child: pw.Text(
                                  '${_c(t.priority.toUpperCase())}  |  ${_c(t.status.toUpperCase())} (${t.completionPercentage}%)',
                                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                                ),
                              ),
                            ],
                          ),
                          if (t.description != null && t.description!.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 3),
                            pw.Text(_c(t.description!), style: const pw.TextStyle(fontSize: 8, color: textDark)),
                          ],
                          pw.SizedBox(height: 4),
                          pw.Text(
                            metaInfo.isNotEmpty ? metaInfo : 'Internal Task',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Row(
                            children: [
                              pw.Text('Assigned Staff: ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: secondaryColor)),
                              pw.Expanded(
                                child: pw.Text(assigneesStr, style: const pw.TextStyle(fontSize: 8, color: textDark)),
                              ),
                            ],
                          ),
                          if (t.attachmentUrl != null && t.attachmentUrl!.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text('Attachment: ${_c(t.attachmentUrl)}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.blue800)),
                          ],
                          if (t.comments.isNotEmpty) ...[
                            pw.SizedBox(height: 4),
                            pw.Text('Task Comments (${t.comments.length}):', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                            ...t.comments.map((c) => pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 6, top: 1),
                                  child: pw.Text(
                                    '* ${_c(c.authorName)} (${_c(c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt)}): "${_c(c.content)}"',
                                    style: const pw.TextStyle(fontSize: 7.5, color: textDark),
                                  ),
                                )),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
          pw.SizedBox(height: 20),

          // 4. Attendance Logs & Employee Daily Work Reports
          _sectionHeader('4. ATTENDANCE & EMPLOYEE DAILY WORK REPORTS (${data.attendanceList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 4),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F5F9),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Text(
              'Summary - Present: ${data.presentCount}   |   Late: ${data.lateCount}   |   Absent: ${data.absentCount}   |   Total Work Hours: ${data.totalHoursWorked.toStringAsFixed(1)} h',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor),
            ),
          ),
          pw.SizedBox(height: 6),
          data.attendanceList.isEmpty
              ? _emptyText('No attendance logs recorded.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Employee', 'Date', 'Check In', 'Check Out', 'Hours', 'Status', 'Method', 'Daily Work Report / Notes'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.6),
                    1: pw.FlexColumnWidth(1.1),
                    2: pw.FlexColumnWidth(1.0),
                    3: pw.FlexColumnWidth(1.0),
                    4: pw.FlexColumnWidth(0.8),
                    5: pw.FlexColumnWidth(0.9),
                    6: pw.FlexColumnWidth(1.1),
                    7: pw.FlexColumnWidth(2.5),
                  },
                  data: data.attendanceList.map((a) => [
                    _c(a.userName),
                    _c(a.date),
                    _c(a.checkIn ?? '-'),
                    _c(a.checkOut ?? '-'),
                    '${a.hoursWorked.toStringAsFixed(1)} h',
                    _c(a.status.toUpperCase()),
                    a.isManual ? 'Manual' : (a.wifiSsid != null ? 'WiFi (${_c(a.wifiSsid)})' : 'Auto'),
                    (a.dailyReport != null && a.dailyReport!.isNotEmpty)
                        ? _c(a.dailyReport)
                        : _c(a.notes ?? 'No report submitted'),
                  ]).toList(),
                ),
          pw.SizedBox(height: 20),

          // 5. CRM & Financial Transactions
          _sectionHeader('5. CRM & FINANCIAL TRANSACTIONS (${data.crmList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.crmList.isEmpty
              ? _emptyText('No financial transactions recorded.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Invoice # / Title', 'Client', 'Billed', 'Paid', 'Outstanding', 'Status', 'Due Date', 'Notes'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.0),
                    1: pw.FlexColumnWidth(1.8),
                    2: pw.FlexColumnWidth(1.1),
                    3: pw.FlexColumnWidth(1.1),
                    4: pw.FlexColumnWidth(1.1),
                    5: pw.FlexColumnWidth(0.9),
                    6: pw.FlexColumnWidth(1.0),
                    7: pw.FlexColumnWidth(1.0),
                  },
                  data: data.crmList.map((c) => [
                    c.invoiceNumber != null ? '[#${_c(c.invoiceNumber)}] ${_c(c.title)}' : _c(c.title),
                    _c(c.clientName),
                    '\$${c.amount.toStringAsFixed(2)}',
                    '\$${c.paidAmount.toStringAsFixed(2)}',
                    '\$${c.outstanding.toStringAsFixed(2)}',
                    _c(c.status.toUpperCase()),
                    _c(c.dueDate != null ? (c.dueDate!.length >= 10 ? c.dueDate!.substring(0, 10) : c.dueDate!) : '-'),
                    _c(c.notes ?? '-'),
                  ]).toList(),
                ),
          pw.SizedBox(height: 20),

          // 6. Expense Entries
          _sectionHeader('6. EXPENSE ENTRIES (${data.expenseList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.expenseList.isEmpty
              ? _emptyText('No expense entries recorded.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Category', 'Description', 'Amount', 'Date', 'Recorded By', 'Status', 'Receipt'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.6),
                    1: pw.FlexColumnWidth(2.4),
                    2: pw.FlexColumnWidth(1.2),
                    3: pw.FlexColumnWidth(1.2),
                    4: pw.FlexColumnWidth(1.4),
                    5: pw.FlexColumnWidth(1.0),
                    6: pw.FlexColumnWidth(1.0),
                  },
                  data: data.expenseList.map((e) => [
                    _c(e.categoryName),
                    _c(e.description.isNotEmpty ? e.description : '-'),
                    '\$${e.amount.toStringAsFixed(2)}',
                    _c(e.date),
                    _c(e.recordedByName),
                    _c(e.status.toUpperCase()),
                    e.receiptUrl != null ? 'Attached' : '-',
                  ]).toList(),
                ),
          pw.SizedBox(height: 20),

          // 7. Penalties Log
          if (data.penaltyList.isNotEmpty) ...[
            _sectionHeader('7. PENALTIES LOG (${data.penaltyList.length})', primaryColor, goldColor),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Employee Name', 'Reason', 'Amount', 'Issue Date', 'Status', 'Notes'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: primaryColor),
              cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.8),
                1: pw.FlexColumnWidth(2.5),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.0),
                5: pw.FlexColumnWidth(1.5),
              },
              data: data.penaltyList.map((p) => [
                _c(p.employeeName),
                _c(p.reason),
                '\$${p.amount.toStringAsFixed(2)}',
                _c(p.date),
                _c(p.status.toUpperCase()),
                _c(p.notes ?? '-'),
              ]).toList(),
            ),
            pw.SizedBox(height: 20),
          ],

          // 8. Comments Log
          _sectionHeader('8. TASK COMMENTS LOG (${data.commentsList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.commentsList.isEmpty
              ? _emptyText('No task comments recorded.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Author Name', 'Task Reference', 'Comment Content', 'Date'],
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                  cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                  oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.5),
                    1: pw.FlexColumnWidth(2.0),
                    2: pw.FlexColumnWidth(4.0),
                    3: pw.FlexColumnWidth(1.2),
                  },
                  data: data.commentsList.map((c) => [
                    _c(c.authorName),
                    _c(c.taskTitle),
                    _c(c.content),
                    _c(c.createdAt.length >= 10 ? c.createdAt.substring(0, 10) : c.createdAt),
                  ]).toList(),
                ),
        ],
      ),
    );

    final bytes = await pdf.save();

    try {
      final printed = await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'SuperAdmin_MasterReport_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      if (!printed) {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'SuperAdmin_MasterReport_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
      }
    } catch (_) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'SuperAdmin_MasterReport_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    }
  }

  // Section Banner Header Widget
  static pw.Widget _sectionHeader(String title, PdfColor bgColor, PdfColor accentColor) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 3.5,
            height: 10,
            decoration: pw.BoxDecoration(
              color: accentColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1)),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              _c(title),
              style: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // KPI Card Widget
  static pw.Widget _kpiBox(String title, String value, PdfColor bg, PdfColor textColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFCBD5E1), width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            _c(title),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            maxLines: 1,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _c(value),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: textColor),
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  static pw.Widget _emptyText(String message) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        _c(message),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
      ),
    );
  }
}
