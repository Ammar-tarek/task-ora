// lib/features/attendance/attendance_qr_screen.dart
//
// Displays the attendance check-in QR code. This replaces the physical NFC
// sticker: instead of tapping a tag, an employee scans this QR with their
// phone camera. The QR encodes ONE shared HTTPS URL:
//
//     https://operations.cashback.marketing/checkin
//
// The URL carries no identity. Scanning it opens the Flutter app (Android App
// Link / iOS Universal Link) or, if the app is not installed, the mobile web
// build — both land on `/checkin`, which creates the check-in for the
// currently authenticated employee (identity comes from the session, never the
// URL). Print this QR or show it on a screen at the check-in location.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';

/// The single shared check-in URL encoded in the QR (and previously in the NFC
/// tag). Change the host here if you deploy on a custom domain.
const String kAttendanceCheckInUrl = 'https://operations.cashback.marketing/checkin';

class AttendanceQrScreen extends StatelessWidget {
  const AttendanceQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Attendance QR')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Scan to Check In',
                    style: AppTextStyles.headlineSm,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Employees scan this code with their phone camera to record '
                    "today's attendance. Print it or show it at the check-in point.",
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // White quiet-zone container so the QR scans reliably on any theme.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: QrImageView(
                      data: kAttendanceCheckInUrl,
                      version: QrVersions.auto,
                      size: 260,
                      backgroundColor: Colors.white,
                      // High error-correction so a printed/worn code still scans.
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    kAttendanceCheckInUrl,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: kAttendanceCheckInUrl),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Check-in link copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
