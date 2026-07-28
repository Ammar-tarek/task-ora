// lib/core/utils/super_admin_pdf_exporter.dart
// Generates and prints/exports a beautifully structured, executive A4 PDF master report.

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
      // Fallback if offline
    }

    final pdf = pw.Document(
      theme: (fontBase != null && fontBold != null)
          ? pw.ThemeData.withFont(base: fontBase, bold: fontBold)
          : null,
    );

    const primaryColor = PdfColor.fromInt(0xFF1E293B); // Slate dark navy
    const secondaryColor = PdfColor.fromInt(0xFF0F172A); // Midnight blue
    const goldColor = PdfColor.fromInt(0xFFC9A84C); // Gold accent
    const lightGreyBg = PdfColor.fromInt(0xFFF8FAFC);
    const borderGrey = PdfColor.fromInt(0xFFE2E8F0);
    const textDark = PdfColor.fromInt(0xFF0F172A);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),

        // Header
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.only(bottom: 6),
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
                          fontSize: 9.5,
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

        // Footer
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 12),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: borderGrey, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Confidential - CashBack Master Operations Report',
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
          // ── Section 1: Executive Overview & KPI ─────────────────────────────
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
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(child: _kpiBox('Total Revenue', '\$${data.totalRevenue.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFF0FDF4), PdfColors.green800)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Paid Revenue', '\$${data.totalPaidRevenue.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFECFDF5), PdfColors.green900)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Total Expenses', '\$${data.totalExpenses.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFFFF7ED), PdfColors.orange800)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(child: _kpiBox('Total Penalties', '\$${data.totalPenalties.toStringAsFixed(2)}', const PdfColor.fromInt(0xFFFEFCE8), goldColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Active Staff Members', '${data.userList.length}', const PdfColor.fromInt(0xFFECFEFF), primaryColor)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _kpiBox('Registered Clients', '${data.clientList.length}', const PdfColor.fromInt(0xFFF0FDFA), primaryColor)),
            ],
          ),
          pw.SizedBox(height: 18),

          // ── Section 2: Tasks Categorized by Department ──────────────────────
          _sectionHeader('2. TASKS CATEGORIZED BY DEPARTMENT (${data.tasksByDepartment.length} DEPARTMENTS)', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.taskList.isEmpty
              ? _emptyText('No tasks recorded.')
              : pw.Column(
                  children: data.tasksByDepartment.entries.map((entry) {
                    final deptName = entry.key;
                    final deptTasks = entry.value;

                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 10),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: lightGreyBg,
                        border: pw.Border.all(color: borderGrey, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'DEPARTMENT: ${_c(deptName.toUpperCase())} (${deptTasks.length} Tasks)',
                                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 6),
                          pw.TableHelper.fromTextArray(
                            headers: ['Task Title', 'Status', 'Priority', 'Progress', 'Assigned Staff', 'Due Date'],
                            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7.5),
                            headerDecoration: const pw.BoxDecoration(color: primaryColor),
                            cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                            oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                            columnWidths: const {
                              0: pw.FlexColumnWidth(2.5),
                              1: pw.FlexColumnWidth(1.1),
                              2: pw.FlexColumnWidth(1.0),
                              3: pw.FlexColumnWidth(0.9),
                              4: pw.FlexColumnWidth(2.0),
                              5: pw.FlexColumnWidth(1.1),
                            },
                            data: deptTasks.map((t) {
                              final assigneesStr = t.assignees.isNotEmpty
                                  ? t.assignees.map((a) => _c(a.name)).join(', ')
                                  : 'Unassigned';
                              return [
                                _c(t.title),
                                _c(t.status.toUpperCase()),
                                _c(t.priority.toUpperCase()),
                                '${t.completionPercentage}%',
                                assigneesStr,
                                _c(t.dueDate != null ? (t.dueDate!.length >= 10 ? t.dueDate!.substring(0, 10) : t.dueDate!) : '-'),
                              ];
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
          pw.SizedBox(height: 18),

          // ── Section 3: Staff & Employees Master Directory & Dossiers ───────
          _sectionHeader('3. STAFF DIRECTORY & DETAILED EMPLOYEE DOSSIERS (${data.userList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.userList.isEmpty
              ? _emptyText('No user profiles registered.')
              : pw.Column(
                  children: [
                    // Summary Table
                    pw.TableHelper.fromTextArray(
                      headers: ['Full Name', 'Role', 'Department', 'Phone', 'Status'],
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                      headerDecoration: const pw.BoxDecoration(color: primaryColor),
                      cellStyle: const pw.TextStyle(fontSize: 8, color: textDark),
                      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                      oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(2.2),
                        1: pw.FlexColumnWidth(1.3),
                        2: pw.FlexColumnWidth(1.8),
                        3: pw.FlexColumnWidth(1.5),
                        4: pw.FlexColumnWidth(1.0),
                      },
                      data: data.userList.map((u) => [
                        _c(u.fullName),
                        _c(u.role.toUpperCase()),
                        _c(u.department),
                        _c(u.phone ?? '-'),
                        u.isActive ? 'Active' : 'Inactive',
                      ]).toList(),
                    ),
                    pw.SizedBox(height: 12),

                    // Employee Detailed Dossiers
                    ...data.employeeDossiers.map((dossier) {
                      final u = dossier.user;
                      return pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 12),
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: borderGrey, width: 0.8),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          color: lightGreyBg,
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // Header
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'EMPLOYEE DOSSIER: ${_c(u.fullName.toUpperCase())}',
                                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                                ),
                                pw.Text(
                                  'Role: ${_c(u.role.toUpperCase())}  |  Dept: ${_c(u.department)}',
                                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: goldColor),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 4),

                            // Assigned Tasks
                            pw.Text('Assigned Tasks (${dossier.assignedTasks.length}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                            dossier.assignedTasks.isEmpty
                                ? _emptyText('No tasks assigned.')
                                : pw.Column(
                                    children: dossier.assignedTasks.map((t) {
                                      return pw.Padding(
                                        padding: const pw.EdgeInsets.only(left: 6, top: 2),
                                        child: pw.Text(
                                          '* ${_c(t.title)} [${_c(t.status.toUpperCase())} - ${t.completionPercentage}%] - Description/Progress: ${_c(t.description ?? "N/A")}',
                                          style: const pw.TextStyle(fontSize: 7.5, color: textDark),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                            pw.SizedBox(height: 4),

                            // Attendance Summary
                            pw.Text('Attendance Logs (${dossier.attendanceLogs.length} entries, Total: ${dossier.totalHours.toStringAsFixed(1)} h):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                            dossier.attendanceLogs.isEmpty
                                ? _emptyText('No attendance logs recorded.')
                                : pw.TableHelper.fromTextArray(
                                    headers: ['Date', 'Check In (12h)', 'Check Out (12h)', 'Hours', 'Status', 'Daily Work Report / Notes'],
                                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7),
                                    headerDecoration: const pw.BoxDecoration(color: primaryColor),
                                    cellStyle: const pw.TextStyle(fontSize: 7, color: textDark),
                                    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                    columnWidths: const {
                                      0: pw.FlexColumnWidth(1.2),
                                      1: pw.FlexColumnWidth(1.1),
                                      2: pw.FlexColumnWidth(1.1),
                                      3: pw.FlexColumnWidth(0.8),
                                      4: pw.FlexColumnWidth(1.0),
                                      5: pw.FlexColumnWidth(2.8),
                                    },
                                    data: dossier.attendanceLogs.map((a) => [
                                      _c(a.date),
                                      _c(a.checkIn12h),
                                      _c(a.checkOut12h),
                                      '${a.hoursWorked.toStringAsFixed(1)}h',
                                      _c(a.status.toUpperCase()),
                                      _c(a.dailyReport ?? a.notes ?? '-'),
                                    ]).toList(),
                                  ),

                            // Penalties
                            if (dossier.penalties.isNotEmpty) ...[
                              pw.SizedBox(height: 4),
                              pw.Text('Penalties Issued (${dossier.penalties.length}, Total: \$${dossier.totalPenalties.toStringAsFixed(2)}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                              ...dossier.penalties.map((p) => pw.Padding(
                                    padding: const pw.EdgeInsets.only(left: 6, top: 1),
                                    child: pw.Text('* ${_c(p.date)} - \$${p.amount.toStringAsFixed(2)}: ${_c(p.reason)} (${_c(p.status)})', style: const pw.TextStyle(fontSize: 7.5, color: textDark)),
                                  )),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
          pw.SizedBox(height: 18),

          // ── Section 4: Attendance Tables per Employee ──────────────────────
          _sectionHeader('4. ATTENDANCE LOGS TABLES PER EMPLOYEE (12-HOUR TIME FORMAT)', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.attendanceList.isEmpty
              ? _emptyText('No attendance records logged.')
              : pw.Column(
                  children: data.employeeDossiers.where((d) => d.attendanceLogs.isNotEmpty).map((dossier) {
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'ATTENDANCE TABLE: ${_c(dossier.user.fullName)} (${dossier.attendanceLogs.length} Records)',
                            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                          ),
                          pw.SizedBox(height: 3),
                          pw.TableHelper.fromTextArray(
                            headers: ['Date (YYYY-MM-DD)', 'Check In (12h)', 'Check Out (12h)', 'Hours Logged', 'Status', 'Method', 'Daily Work Report / Notes'],
                            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7.5),
                            headerDecoration: const pw.BoxDecoration(color: primaryColor),
                            cellStyle: const pw.TextStyle(fontSize: 7.5, color: textDark),
                            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
                            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
                            oddRowDecoration: const pw.BoxDecoration(color: lightGreyBg),
                            columnWidths: const {
                              0: pw.FlexColumnWidth(1.4),
                              1: pw.FlexColumnWidth(1.2),
                              2: pw.FlexColumnWidth(1.2),
                              3: pw.FlexColumnWidth(1.0),
                              4: pw.FlexColumnWidth(1.0),
                              5: pw.FlexColumnWidth(1.1),
                              6: pw.FlexColumnWidth(2.6),
                            },
                            data: dossier.attendanceLogs.map((a) => [
                              _c(a.date),
                              _c(a.checkIn12h),
                              _c(a.checkOut12h),
                              '${a.hoursWorked.toStringAsFixed(1)} h',
                              _c(a.status.toUpperCase()),
                              a.isManual ? 'Manual' : (a.wifiSsid != null ? 'WiFi' : 'Auto'),
                              _c(a.dailyReport ?? a.notes ?? '-'),
                            ]).toList(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
          pw.SizedBox(height: 18),

          // ── Section 5: Client Master Directory & Detailed Dossiers ─────────
          _sectionHeader('5. CLIENTS DIRECTORY & DETAILED CLIENT DOSSIERS (${data.clientList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.clientList.isEmpty
              ? _emptyText('No client profiles registered.')
              : pw.Column(
                  children: data.clientDossiers.map((clientDossier) {
                    final c = clientDossier.client;
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 12),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: borderGrey, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: lightGreyBg,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // Header
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'CLIENT DOSSIER: ${_c(c.companyName.toUpperCase())}',
                                style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: secondaryColor),
                              ),
                              pw.Text(
                                'Contact: ${_c(c.contactName ?? "-")}  |  Status: ${_c(c.status.toUpperCase())}',
                                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: goldColor),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 4),

                          // Contact Info
                          pw.Text(
                            'Email: ${_c(c.email ?? "-")}  |  Phone: ${_c(c.phone ?? "-")}  |  Notes: ${_c(c.notes ?? "-")}',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                          ),
                          pw.SizedBox(height: 6),

                          // Client Tasks
                          pw.Text('Client Tasks (${clientDossier.tasks.length}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                          clientDossier.tasks.isEmpty
                              ? _emptyText('No tasks associated.')
                              : pw.Column(
                                  children: clientDossier.tasks.map((t) => pw.Padding(
                                        padding: const pw.EdgeInsets.only(left: 6, top: 1),
                                        child: pw.Text(
                                          '* ${_c(t.title)} [${_c(t.status.toUpperCase())} - ${t.completionPercentage}%] - Assignees: ${_c(t.assignees.map((a) => a.name).join(", "))}',
                                          style: const pw.TextStyle(fontSize: 7.5, color: textDark),
                                        ),
                                      )).toList(),
                                ),
                          pw.SizedBox(height: 4),

                          // Client Financials / CRM
                          pw.Text('Client Financials & Contracts (${clientDossier.crmEntries.length}, Total Contract: \$${clientDossier.totalContractValue.toStringAsFixed(2)}, Paid: \$${clientDossier.totalPaid.toStringAsFixed(2)}, Outstanding: \$${clientDossier.totalOutstanding.toStringAsFixed(2)}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                          clientDossier.crmEntries.isEmpty
                              ? _emptyText('No financial entries recorded.')
                              : pw.TableHelper.fromTextArray(
                                  headers: ['Title / Invoice #', 'Contract Value', 'Paid Amount', 'Outstanding', 'Status', 'Due Date'],
                                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7),
                                  headerDecoration: const pw.BoxDecoration(color: primaryColor),
                                  cellStyle: const pw.TextStyle(fontSize: 7, color: textDark),
                                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                  columnWidths: const {
                                    0: pw.FlexColumnWidth(2.2),
                                    1: pw.FlexColumnWidth(1.2),
                                    2: pw.FlexColumnWidth(1.2),
                                    3: pw.FlexColumnWidth(1.2),
                                    4: pw.FlexColumnWidth(1.0),
                                    5: pw.FlexColumnWidth(1.2),
                                  },
                                  data: clientDossier.crmEntries.map((crm) => [
                                    crm.invoiceNumber != null ? '[#${_c(crm.invoiceNumber)}] ${_c(crm.title)}' : _c(crm.title),
                                    '\$${crm.amount.toStringAsFixed(2)}',
                                    '\$${crm.paidAmount.toStringAsFixed(2)}',
                                    '\$${crm.outstanding.toStringAsFixed(2)}',
                                    _c(crm.status.toUpperCase()),
                                    _c(crm.dueDate != null ? (crm.dueDate!.length >= 10 ? crm.dueDate!.substring(0, 10) : crm.dueDate!) : '-'),
                                  ]).toList(),
                                ),
                          pw.SizedBox(height: 4),

                          // Client Meetings & Events
                          pw.Text('Scheduled Meetings & Events (${clientDossier.meetings.length}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                          clientDossier.meetings.isEmpty
                              ? _emptyText('No meetings scheduled.')
                              : pw.Column(
                                  children: clientDossier.meetings.map((m) => pw.Padding(
                                        padding: const pw.EdgeInsets.only(left: 6, top: 1),
                                        child: pw.Text(
                                          '* ${_c(m.title)} (${_c(m.startTime.length >= 16 ? m.startTime.substring(0, 16) : m.startTime)}) - Status: ${_c(m.status)} - Location/Notes: ${_c(m.location ?? m.meetingNotes ?? "N/A")}',
                                          style: const pw.TextStyle(fontSize: 7.5, color: textDark),
                                        ),
                                      )).toList(),
                                ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
          pw.SizedBox(height: 18),

          // ── Section 6: Expenses & Penalties Overview ───────────────────────
          _sectionHeader('6. FINANCIAL EXPENSES & PENALTIES SUMMARY', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Expenses by Category (${data.expenseList.length} entries, \$${data.totalExpenses.toStringAsFixed(2)}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.SizedBox(height: 4),
                    data.expenseCategories.isEmpty
                        ? _emptyText('No expense entries.')
                        : pw.TableHelper.fromTextArray(
                            headers: ['Category', 'Entries', 'Total Amount'],
                            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7),
                            headerDecoration: const pw.BoxDecoration(color: primaryColor),
                            cellStyle: const pw.TextStyle(fontSize: 7, color: textDark),
                            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            data: data.expenseCategories.map((c) => [
                              _c(c.categoryName),
                              '${c.count}',
                              '\$${c.totalAmount.toStringAsFixed(2)}',
                            ]).toList(),
                          ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Penalties Log (${data.penaltyList.length} entries, \$${data.totalPenalties.toStringAsFixed(2)}):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.SizedBox(height: 4),
                    data.penaltyList.isEmpty
                        ? _emptyText('No penalty logs.')
                        : pw.TableHelper.fromTextArray(
                            headers: ['Employee', 'Reason', 'Amount', 'Date'],
                            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 7),
                            headerDecoration: const pw.BoxDecoration(color: primaryColor),
                            cellStyle: const pw.TextStyle(fontSize: 7, color: textDark),
                            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            data: data.penaltyList.map((p) => [
                              _c(p.employeeName),
                              _c(p.reason),
                              '\$${p.amount.toStringAsFixed(2)}',
                              _c(p.date),
                            ]).toList(),
                          ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // ── Section 7: Task Comments Log ────────────────────────────────────
          _sectionHeader('7. TASK COMMENTS LOG (${data.commentsList.length})', primaryColor, goldColor),
          pw.SizedBox(height: 6),
          data.commentsList.isEmpty
              ? _emptyText('No task comments logged.')
              : pw.TableHelper.fromTextArray(
                  headers: ['Author Name', 'Task Title', 'Comment Content', 'Date'],
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
        border: pw.Border.all(color: PdfColor.fromInt(0xFFCBD5E1), width: 0.6),
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
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
      ),
    );
  }
}
