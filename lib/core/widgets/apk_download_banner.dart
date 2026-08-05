// lib/core/widgets/apk_download_banner.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ApkDownloadBanner extends StatefulWidget {
  const ApkDownloadBanner({super.key});

  static const String apkUrl =
      'https://github.com/Ammar-tarek/task-ora/releases/download/1.6.0/app-release.apk';

  static Future<void> downloadApk() async {
    final uri = Uri.parse(apkUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  State<ApkDownloadBanner> createState() => _ApkDownloadBannerState();
}

class _ApkDownloadBannerState extends State<ApkDownloadBanner> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
