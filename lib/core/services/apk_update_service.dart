import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:background_downloader/background_downloader.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class ApkUpdateService {
  static bool _checking = false;

  /// Checks GitHub Releases API (and Supabase app_versions as fallback) and prompts the user to download and install
  /// if a newer version is available.
  ///
  /// Set [isManual] to true for user-initiated checks (e.g. Settings -> Check for Updates).
  /// Manual checks display a loading dialog during lookup, an Up-To-Date dialog if no update is available,
  /// and an Error dialog if the check fails.
  /// Automatic checks (isManual = false) run silently unless an update is available.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool isManual = false,
    bool showNoUpdateToast = false, // Backwards compatibility: treated as isManual
    bool forceDialog = false,
  }) async {
    if (kIsWeb) return;
    final manual = isManual || showNoUpdateToast;
    if (_checking) return;
    _checking = true;

    BuildContext? loadingDialogContext;

    if (manual && context.mounted) {
      _showLoadingDialog(context, onCreated: (dialogCtx) {
        loadingDialogContext = dialogCtx;
      });
    }

    void dismissLoadingDialog() {
      if (loadingDialogContext != null && loadingDialogContext!.mounted) {
        Navigator.of(loadingDialogContext!, rootNavigator: true).pop();
        loadingDialogContext = null;
      }
    }

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.0.0"

      Map<String, dynamic>? data;

      // 1. Fetch latest release directly from GitHub Releases API
      try {
        final response = await http.get(
          Uri.parse(
              'https://api.github.com/repos/Ammar-tarek/task-ora/releases/latest'),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'TaskOra-App',
          },
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final ghData = jsonDecode(response.body) as Map<String, dynamic>;
          final rawTag = (ghData['tag_name'] as String? ?? '').trim();
          final tagName =
              rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
          final body = ghData['body'] as String? ??
              'New version available on GitHub.';
          final assets = (ghData['assets'] as List?) ?? [];

          String downloadUrl = '';
          int fileSize = 0;
          for (final asset in assets) {
            final name = (asset['name'] as String? ?? '').toLowerCase();
            if (name.endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String? ?? '';
              fileSize = (asset['size'] as num? ?? 0).toInt();
              break;
            }
          }

          if (tagName.isNotEmpty && downloadUrl.isNotEmpty) {
            data = {
              'latest_version': tagName,
              'min_required_version': '1.0.0',
              'download_url': downloadUrl,
              'file_size': fileSize,
              'release_notes': body,
              'is_mandatory': false,
            };
          }
        }
      } catch (_) {}

      // 2. Fallback to Supabase app_versions if GitHub API did not return a release asset
      if (data == null) {
        try {
          data = await SupabaseService.client
              .from('app_versions')
              .select()
              .eq('platform', 'android')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (_) {
          data = await SupabaseService.adminClient
              .from('app_versions')
              .select()
              .eq('platform', 'android')
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
        }
      }

      if (data == null) {
        dismissLoadingDialog();
        if (manual && context.mounted) {
          _showErrorDialog(
            context,
            onRetry: () => checkForUpdates(
              context,
              isManual: true,
              forceDialog: forceDialog,
            ),
          );
        }
        return;
      }

      final latestVersion = data['latest_version'] as String? ?? '1.0.0';
      final minRequiredVersion =
          data['min_required_version'] as String? ?? '1.0.0';
      final downloadUrl = data['download_url'] as String? ?? '';
      final fileSize = (data['file_size'] as num? ?? 0).toInt();
      final releaseNotes = data['release_notes'] as String? ??
          'Performance improvements and bug fixes.';
      final isMandatory = (data['is_mandatory'] as bool? ?? false) ||
          _isNewerVersion(currentVersion, minRequiredVersion);

      final hasNewVersion = _isNewerVersion(currentVersion, latestVersion);

      dismissLoadingDialog();

      if ((hasNewVersion || forceDialog) && downloadUrl.isNotEmpty) {
        if (context.mounted) {
          _showUpdateDialog(
            context,
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl,
            expectedFileSize: fileSize,
            notes: releaseNotes,
            isMandatory: isMandatory,
          );
        }
      } else if (manual && context.mounted) {
        _showUpToDateDialog(
          context,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
        );
      }
    } catch (e) {
      dismissLoadingDialog();
      if (manual && context.mounted) {
        _showErrorDialog(
          context,
          onRetry: () => checkForUpdates(
            context,
            isManual: true,
            forceDialog: forceDialog,
          ),
        );
      }
    } finally {
      _checking = false;
    }
  }

  /// Helper to compare version strings (e.g. "1.2.0" > "1.0.0")
  static bool _isNewerVersion(String current, String latest) {
    try {
      final c = current
          .split('.')
          .map((e) => int.tryParse(e.split('+').first) ?? 0)
          .toList();
      final l = latest
          .split('.')
          .map((e) => int.tryParse(e.split('+').first) ?? 0)
          .toList();
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

  /// Non-dismissible Loading Dialog shown during manual update checks
  static void _showLoadingDialog(
    BuildContext context, {
    required Function(BuildContext) onCreated,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        onCreated(dialogCtx);
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.surfaceContainerLowest,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: AppColors.gold,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Checking for Updates...',
                    style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we check for the latest version.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Success dialog shown when application is already on the latest version (manual check)
  static void _showUpToDateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.statusDone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.statusDone,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "You're Up To Date",
                style: AppTextStyles.headlineSm.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          'Current Version',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentVersion,
                          style: AppTextStyles.labelMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      height: 28,
                      width: 1,
                      color: AppColors.outlineVariant,
                    ),
                    Column(
                      children: [
                        Text(
                          'Latest Version',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          latestVersion,
                          style: AppTextStyles.labelMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.statusDone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your application is already running the latest version.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Error dialog shown when update check fails (manual check)
  static void _showErrorDialog(
    BuildContext context, {
    required VoidCallback onRetry,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.error,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unable to Check for Updates',
                style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "We couldn't verify the latest version. Please try again later.",
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Close',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                onRetry();
              },
              child: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Displays the Update Available, Download Progress, and Download Completed Dialog
  static void _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String downloadUrl,
    int expectedFileSize = 0,
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
        bool downloadFailed = false;
        String statusText = 'Downloading version $latestVersion';
        String? downloadedPath;

        return PopScope(
          canPop: !isMandatory && !downloading,
          child: StatefulBuilder(
            builder: (context, setState) {
              Future<void> startDownloadAndInstall() async {
                setState(() {
                  downloading = true;
                  downloaded = false;
                  downloadFailed = false;
                  statusText = 'Downloading version $latestVersion';
                  progress = 0.0;
                });

                bool success = false;

                try {
                  final task = DownloadTask(
                    url: downloadUrl,
                    filename: 'task_ora_v$latestVersion.apk',
                    directory: 'updates',
                    baseDirectory: BaseDirectory.applicationSupport,
                    updates: Updates.statusAndProgress,
                  );

                  FileDownloader().configureNotification(
                    running: TaskNotification('Updating Task Ora',
                        'Downloading version $latestVersion…'),
                    complete: TaskNotification('Update Downloaded',
                        'Tap to install version $latestVersion'),
                    error: const TaskNotification(
                        'Update Failed', 'Could not download the update.'),
                  );

                  final updateSubscription = FileDownloader().updates.listen((update) {
                    if (update is TaskProgressUpdate && update.task.taskId == task.taskId) {
                      if (context.mounted && downloading) {
                        setState(() {
                          if (update.progress >= 0) {
                            progress = update.progress;
                          }
                        });
                      }
                    }
                  });

                  final result = await FileDownloader().download(
                    task,
                    onProgress: (p) {
                      if (context.mounted && downloading && p >= 0) {
                        setState(() {
                          progress = p;
                        });
                      }
                    },
                  );

                  await updateSubscription.cancel();

                  if (result.status == TaskStatus.complete) {
                    final path = await task.filePath();
                    downloadedPath = path;
                    success = true;
                    if (context.mounted) {
                      setState(() {
                        downloading = false;
                        downloaded = true;
                        progress = 1.0;
                        statusText =
                            'Version $latestVersion has been downloaded successfully.';
                      });
                    }
                    if (path.isNotEmpty) {
                      await OpenFilex.open(path);
                    }
                    return;
                  }
                } catch (_) {}

                // HTTP Stream Fallback if FileDownloader didn't complete
                if (!success) {
                  try {
                    final task = DownloadTask(
                      url: downloadUrl,
                      filename: 'task_ora_v$latestVersion.apk',
                      directory: 'updates',
                      baseDirectory: BaseDirectory.applicationSupport,
                    );
                    final filePath = await task.filePath();

                    final client = http.Client();
                    final request = http.Request('GET', Uri.parse(downloadUrl));
                    final response = await client.send(request);

                    if (response.statusCode == 200) {
                      int total = response.contentLength ?? 0;
                      if (total <= 0) {
                        final headerLen = response.headers['content-length'];
                        if (headerLen != null) {
                          total = int.tryParse(headerLen) ?? 0;
                        }
                      }
                      if (total <= 0 && expectedFileSize > 0) {
                        total = expectedFileSize;
                      }

                      int received = 0;

                      final file = File(filePath);
                      await file.parent.create(recursive: true);
                      final sink = file.openWrite();

                      await response.stream.listen(
                        (chunk) {
                          received += chunk.length;
                          sink.add(chunk);
                          if (context.mounted && downloading) {
                            setState(() {
                              if (total > 0) {
                                progress = (received / total).clamp(0.01, 1.0);
                              } else {
                                progress = (progress + 0.02).clamp(0.01, 0.95);
                              }
                            });
                          }
                        },
                        cancelOnError: true,
                      ).asFuture();

                      await sink.flush();
                      await sink.close();
                      client.close();

                      if (await file.exists() && (await file.length()) > 0) {
                        downloadedPath = filePath;
                        success = true;
                        if (context.mounted) {
                          setState(() {
                            downloading = false;
                            downloaded = true;
                            progress = 1.0;
                            statusText =
                                'Version $latestVersion has been downloaded successfully.';
                          });
                        }
                        await OpenFilex.open(filePath);
                        return;
                      }
                    }
                  } catch (_) {}
                }

                if (context.mounted && !success) {
                  setState(() {
                    downloading = false;
                    downloadFailed = true;
                    statusText =
                        'Download failed. Please check your internet and try again.';
                  });
                }
              }

              // Build dialog content based on current downloading state
              Widget content;
              List<Widget> actions;
              Widget titleWidget;

              if (downloading) {
                // Download Progress View
                final percentInt = (progress * 100).clamp(0, 100).toInt();
                titleWidget = Text(
                  'Downloading Update...',
                  style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                );

                content = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 10,
                        color: AppColors.gold,
                        backgroundColor: AppColors.outlineVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            statusText,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          '$percentInt%',
                          style: AppTextStyles.labelMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                actions = [];
              } else if (downloaded) {
                // Download Completed View
                titleWidget = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.statusDone.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.statusDone,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Update Ready',
                        style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                      ),
                    ),
                  ],
                );

                content = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Version $latestVersion has been downloaded successfully.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                );

                actions = [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      if (downloadedPath != null &&
                          downloadedPath!.isNotEmpty) {
                        await OpenFilex.open(downloadedPath!);
                      }
                    },
                    icon: const Icon(Icons.install_mobile, size: 18),
                    label: const Text(
                      'Install Now',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ];
              } else if (downloadFailed) {
                // Download Failed View
                titleWidget = Text(
                  'Download Failed',
                  style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                );

                content = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      statusText,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ],
                );

                actions = [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Close',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: startDownloadAndInstall,
                    child: const Text(
                      'Retry Download',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ];
              } else {
                // Update Available View
                titleWidget = Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: AppColors.gold,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'New Version Available',
                        style: AppTextStyles.headlineSm.copyWith(fontSize: 18),
                      ),
                    ),
                  ],
                );

                content = SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Current Version',
                                  style: AppTextStyles.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentVersion,
                                  style: AppTextStyles.labelMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              height: 24,
                              width: 1,
                              color: AppColors.outlineVariant,
                            ),
                            Column(
                              children: [
                                Text(
                                  'Latest Version',
                                  style: AppTextStyles.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  latestVersion,
                                  style: AppTextStyles.labelMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildReleaseNotes(notes),
                      if (isMandatory) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: AppColors.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This update is required to continue using the app.',
                                  style: AppTextStyles.bodySm.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );

                actions = [
                  if (!isMandatory)
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Later',
                        style: AppTextStyles.labelMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: startDownloadAndInstall,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Update Now',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ];
              }

              return AlertDialog(
                backgroundColor: AppColors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: titleWidget,
                content: content,
                actions: actions,
              );
            },
          ),
        );
      },
    );
  }

  /// Formats release notes with clean bullet points
  static Widget _buildReleaseNotes(String notes) {
    final lines = notes
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's New",
          style:
              AppTextStyles.labelMd.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...lines.map((line) {
          final text =
              line.startsWith('•') || line.startsWith('-') ? line : '• $line';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              text,
              style: AppTextStyles.bodySm
                  .copyWith(color: AppColors.onSurfaceVariant),
            ),
          );
        }),
      ],
    );
  }
}

