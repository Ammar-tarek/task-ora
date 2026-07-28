// lib/core/services/apk_update_service.dart
// In-app version checker and APK downloader/installer service using background_downloader and open_filex.

import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class ApkUpdateService {
  static bool _checking = false;

  /// Checks Supabase app_versions table and prompts the user to download and install
  /// if a newer version is available.
  static Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateToast = false}) async {
    if (_checking) return;
    _checking = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.0.0"

      final data = await SupabaseService.client
          .from('app_versions')
          .select()
          .eq('platform', 'android')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('App is up to date.')),
          );
        }
        _checking = false;
        return;
      }

      final latestVersion = data['latest_version'] as String? ?? '1.0.0';
      final minRequiredVersion = data['min_required_version'] as String? ?? '1.0.0';
      final downloadUrl = data['download_url'] as String? ?? '';
      final releaseNotes = data['release_notes'] as String? ?? 'Performance improvements and bug fixes.';
      final isMandatory = (data['is_mandatory'] as bool? ?? false) || _isNewerVersion(currentVersion, minRequiredVersion);

      if (_isNewerVersion(currentVersion, latestVersion) && downloadUrl.isNotEmpty) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl,
            notes: releaseNotes,
            isMandatory: isMandatory,
          );
        }
      } else if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CashBack is up to date (v$currentVersion).')),
        );
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  /// Helper to compare version strings (e.g. "1.2.0" > "1.0.0")
  static bool _isNewerVersion(String current, String latest) {
    try {
      final c = current.split('.').map((e) => int.tryParse(e.split('+').first) ?? 0).toList();
      final l = latest.split('.').map((e) => int.tryParse(e.split('+').first) ?? 0).toList();
      final maxLen = c.length > l.length ? c.length : l.length;
      for (int i = 0; i < maxLen; i++) {
        final curr = i < c.length ? c[i] : 0;
        final lat = i < l.length ? l[i] : 0;
        if (lat > curr) return true;
        if (lat < curr) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Displays the Update Dialog with background_downloader progress bar
  static void _showUpdateDialog(
    BuildContext context, {
    required String latestVersion,
    required String downloadUrl,
    required String notes,
    required bool isMandatory,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (ctx) {
        double progress = 0.0;
        bool downloading = false;
        bool downloaded = false;
        String statusText = 'Ready to download update.';
        String? downloadedPath;

        return PopScope(
          canPop: !isMandatory && !downloading,
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> startDownloadAndInstall() async {
                setState(() {
                  downloading = true;
                  downloaded = false;
                  statusText = 'Starting download…';
                  progress = 0.01;
                });

                try {
                  final task = DownloadTask(
                    url: downloadUrl,
                    filename: 'task_ora_v$latestVersion.apk',
                    directory: 'updates',
                    baseDirectory: BaseDirectory.applicationSupport,
                    updates: Updates.statusAndProgress,
                  );

                  FileDownloader().configureNotification(
                    running: TaskNotification('Updating CashBack', 'Downloading version $latestVersion…'),
                    complete: TaskNotification('Update Downloaded', 'Tap to install version $latestVersion'),
                    error: const TaskNotification('Update Failed', 'Could not download the update.'),
                  );

                  FileDownloader().registerCallbacks(
                    taskProgressCallback: (taskProgress) {
                      if (context.mounted) {
                        setState(() {
                          progress = taskProgress.progress;
                          statusText = 'Downloading: ${(progress * 100).toInt()}%';
                        });
                      }
                    },
                    taskStatusCallback: (taskStatusUpdate) async {
                      if (taskStatusUpdate.status == TaskStatus.complete) {
                        final path = await task.filePath();
                        downloadedPath = path;
                        if (context.mounted) {
                          setState(() {
                            downloading = false;
                            downloaded = true;
                            progress = 1.0;
                            statusText = 'Download complete! Launching installer…';
                          });
                        }
                        // Launch native APK installer using OpenFilex
                        if (path.isNotEmpty) {
                          await OpenFilex.open(path);
                        }
                      } else if (taskStatusUpdate.status == TaskStatus.failed ||
                          taskStatusUpdate.status == TaskStatus.canceled) {
                        if (context.mounted) {
                          setState(() {
                            downloading = false;
                            statusText = 'Download failed. Tap to retry.';
                          });
                        }
                      }
                    },
                  );

                  final result = await FileDownloader().download(task);
                  if (result.status == TaskStatus.complete) {
                    final path = await task.filePath();
                    if (path.isNotEmpty) {
                      await OpenFilex.open(path);
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() {
                      downloading = false;
                      statusText = 'Error: Unable to download update.';
                    });
                  }
                }
              }

              return AlertDialog(
                backgroundColor: AppColors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.system_update_outlined, color: AppColors.gold, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'New Version $latestVersion Available',
                        style: AppTextStyles.headlineSm.copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Release Notes:', style: AppTextStyles.labelMd),
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        style: AppTextStyles.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (downloading || downloaded) ...[
                        LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          color: AppColors.gold,
                          backgroundColor: AppColors.outlineVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          statusText,
                          style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  if (!isMandatory && !downloading)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Later', style: AppTextStyles.labelMd),
                    ),
                  if (!downloaded)
                    ElevatedButton.icon(
                      onPressed: downloading ? null : startDownloadAndInstall,
                      icon: downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(downloading ? 'Downloading…' : 'Update & Install'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (downloadedPath != null && downloadedPath!.isNotEmpty) {
                          await OpenFilex.open(downloadedPath!);
                        }
                      },
                      icon: const Icon(Icons.install_mobile, size: 18),
                      label: const Text('Install APK'),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
