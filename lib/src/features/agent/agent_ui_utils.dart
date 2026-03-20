import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../workspace/domain/forge_agent_entities.dart';
import '../workspace/domain/forge_workspace_entities.dart';

enum ForgeAgentFileVisualState {
  read,
  modified,
  created,
  validationFailed,
  readyForReview,
}

class ForgeAgentFileVisual {
  const ForgeAgentFileVisual({
    required this.path,
    required this.state,
    required this.label,
    this.action,
  });

  final String path;
  final ForgeAgentFileVisualState state;
  final String label;
  final String? action;
}

String formatAgentStatusLabel(ForgeAgentTask task) {
  if (task.needsApproval) {
    return 'Approval Needed';
  }
  return switch (task.status) {
    ForgeAgentTaskStatus.queued => 'Queued',
    ForgeAgentTaskStatus.running => 'Running',
    ForgeAgentTaskStatus.waitingForInput => 'Waiting',
    ForgeAgentTaskStatus.completed => 'Done',
    ForgeAgentTaskStatus.failed => 'Failed',
    ForgeAgentTaskStatus.cancelled => 'Cancelled',
  };
}

IconData agentStatusIcon(ForgeAgentTask task) {
  if (task.needsApproval) {
    return Icons.pending_actions_rounded;
  }
  return switch (task.status) {
    ForgeAgentTaskStatus.queued => Icons.schedule_rounded,
    ForgeAgentTaskStatus.running => Icons.play_circle_fill_rounded,
    ForgeAgentTaskStatus.waitingForInput => Icons.pause_circle_filled_rounded,
    ForgeAgentTaskStatus.completed => Icons.check_circle_rounded,
    ForgeAgentTaskStatus.failed => Icons.error_rounded,
    ForgeAgentTaskStatus.cancelled => Icons.cancel_rounded,
  };
}

Color agentStatusColor(ForgeAgentTask task) {
  if (task.needsApproval) {
    return ForgePalette.warning;
  }
  return switch (task.status) {
    ForgeAgentTaskStatus.queued => ForgePalette.primaryAccent,
    ForgeAgentTaskStatus.running => ForgePalette.glowAccent,
    ForgeAgentTaskStatus.waitingForInput => ForgePalette.warning,
    ForgeAgentTaskStatus.completed => ForgePalette.success,
    ForgeAgentTaskStatus.failed => ForgePalette.error,
    ForgeAgentTaskStatus.cancelled => ForgePalette.textMuted,
  };
}

Duration agentElapsed(ForgeAgentTask task) {
  final end = task.completedAt ?? task.failedAt ?? task.cancelledAt ?? DateTime.now();
  final start = task.startedAt ?? task.createdAt;
  final duration = end.difference(start);
  if (duration.isNegative) {
    return Duration.zero;
  }
  return duration;
}

String formatElapsed(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
  return '${duration.inSeconds}s';
}

String formatRelativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inSeconds < 45) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String formatAbsoluteTime(DateTime time) {
  return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String taskHeadline(ForgeAgentTask task) {
  final prompt = task.prompt.trim();
  if (prompt.length <= 80) {
    return prompt;
  }
  return '${prompt.substring(0, 80)}...';
}

String queueEtaLabel(int position) {
  if (position <= 1) {
    return 'Next after active run';
  }
  return 'Behind ${position - 1} queued task${position - 1 == 1 ? '' : 's'}';
}

int? countMetadataList(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is List) {
    return value.whereType<String>().length;
  }
  final countKey = '${key}Count';
  final countValue = data[countKey];
  if (countValue is num) {
    return countValue.toInt();
  }
  return null;
}

String approvalTypeLabel(ForgeAgentTaskApprovalType type) {
  return switch (type) {
    ForgeAgentTaskApprovalType.applyChanges => 'Apply changes',
    ForgeAgentTaskApprovalType.commitChanges => 'Commit',
    ForgeAgentTaskApprovalType.openPullRequest => 'Open PR',
    ForgeAgentTaskApprovalType.mergePullRequest => 'Merge',
    ForgeAgentTaskApprovalType.deployWorkflow => 'Deploy',
    ForgeAgentTaskApprovalType.resumeTask => 'Resume',
    ForgeAgentTaskApprovalType.riskyOperation => 'Risky action',
  };
}

String formatFailureCategoryLabel(String? category) {
  switch (category?.trim()) {
    case 'workspace':
      return 'Workspace mismatch';
    case 'import':
      return 'Import or module';
    case 'typecheck':
      return 'Type or compile';
    case 'syntax':
      return 'Syntax';
    case 'test':
      return 'Test failure';
    case 'build':
      return 'Build';
    case 'lint':
      return 'Lint';
    case 'ci':
      return 'Remote CI';
    default:
      return '';
  }
}

String formatWorkspaceSourceLabel(String? source) {
  switch (source?.trim()) {
    case 'sandbox_workspace':
      return 'Sandbox workspace';
    case 'repo_sync':
      return 'Synced draft';
    case 'local_workspace':
      return 'Local workspace';
    default:
      return '';
  }
}

List<String> buildEventMetadata(ForgeAgentTaskEvent event) {
  final items = <String>[];
  void add(String label) {
    if (label.trim().isEmpty || items.contains(label)) {
      return;
    }
    items.add(label);
  }

  final data = event.data;
  final path = data['path'];
  if (path is String && path.trim().isNotEmpty) {
    add(path.trim());
  }
  final source = data['source'];
  if (source is String && source.trim().isNotEmpty) {
    add(source.trim());
  }
  final attempt = data['attempt'];
  if (attempt is num) {
    add('Retry #${attempt.toInt()}');
  }
  final fileCount = data['fileCount'];
  if (fileCount is num) {
    add('${fileCount.toInt()} files');
  }
  final passNumber = data['passNumber'];
  final totalPasses = data['totalPasses'];
  if (passNumber is num && totalPasses is num && totalPasses.toInt() > 0) {
    add('Pass ${passNumber.toInt()}/${totalPasses.toInt()}');
  } else if (passNumber is num) {
    add('Pass ${passNumber.toInt()}');
  }
  final selectedFileCount = countMetadataList(data, 'selectedFiles');
  if (selectedFileCount != null && selectedFileCount > 0) {
    add('$selectedFileCount editable in current wave');
  }
  final inspectedFileCount = countMetadataList(data, 'inspectedFiles');
  if (inspectedFileCount != null && inspectedFileCount > 0) {
    add('$inspectedFileCount inspected');
  }
  final dependencyFileCount = countMetadataList(data, 'dependencyFiles');
  if (dependencyFileCount != null && dependencyFileCount > 0) {
    add('$dependencyFileCount dependencies');
  }
  final globalContextFileCount = countMetadataList(data, 'globalContextFiles');
  if (globalContextFileCount != null && globalContextFileCount > 0) {
    add('$globalContextFileCount global');
  }
  final editCount = data['editCount'];
  if (editCount is num) {
    add('${editCount.toInt()} diffs');
  }
  final diffCount = data['diffCount'];
  if (diffCount is num) {
    add('${diffCount.toInt()} diffs');
  }
  final estimatedTokens = data['estimatedTokens'];
  if (estimatedTokens is num) {
    add('${estimatedTokens.toInt()} tokens');
  }
  final mode = data['mode'];
  if (mode is String && mode.trim().isNotEmpty) {
    add(mode.trim());
  }
  final provider = data['provider'];
  if (provider is String && provider.trim().isNotEmpty) {
    add(provider.trim());
  }
  final model = data['model'];
  if (model is String && model.trim().isNotEmpty) {
    add(model.trim());
  }
  final toolName = data['toolName'];
  if (toolName is String && toolName.trim().isNotEmpty) {
    add(toolName.trim());
  }
  final toolKind = data['toolKind'];
  if (toolKind is String && toolKind.trim().isNotEmpty) {
    add(toolKind.trim().replaceAll('_', ' '));
  }
  final workflowCategory = data['workflowCategory'];
  if (workflowCategory is String && workflowCategory.trim().isNotEmpty) {
    add(workflowCategory.trim());
  }
  final failureCategory = formatFailureCategoryLabel(
    data['failureCategory'] as String?,
  );
  if (failureCategory.isNotEmpty) {
    add(failureCategory);
  }
  final repoSizeClass = data['repoSizeClass'];
  if (repoSizeClass is String && repoSizeClass.trim().isNotEmpty) {
    add(repoSizeClass.trim());
  }
  final findings = data['findings'];
  if (findings is List) {
    final count = findings.whereType<Map>().length;
    if (count > 0) {
      add('$count findings');
    }
  }
  final durationMs = data['durationMs'];
  if (durationMs is num && durationMs.toInt() > 0) {
    add(formatElapsed(Duration(milliseconds: durationMs.toInt())));
  }
  final repairTargetCount = countMetadataList(data, 'repairTargetPaths');
  if (repairTargetCount != null && repairTargetCount > 0) {
    add('$repairTargetCount targeted');
  }
  final workspaceSource = formatWorkspaceSourceLabel(
    data['workspaceSourceOfTruth'] as String?,
  );
  if (workspaceSource.isNotEmpty) {
    add(workspaceSource);
  }
  final contextStrategy = data['contextStrategy'];
  if (contextStrategy is String && contextStrategy.trim().isNotEmpty) {
    add(contextStrategy.trim());
  }
  final focusModules = data['focusModules'];
  if (focusModules is List) {
    final count = focusModules.whereType<String>().where((value) => value.trim().isNotEmpty).length;
    if (count > 0) {
      add('$count modules');
    }
  }
  final hydratedPathCount = countMetadataList(data, 'hydratedPaths');
  if (hydratedPathCount != null && hydratedPathCount > 0) {
    add('$hydratedPathCount hydrated');
  }
  final moduleCount = data['moduleCount'];
  if (moduleCount is num) {
    add('${moduleCount.toInt()} total modules');
  }
  final architectureZoneCount = data['architectureZoneCount'];
  if (architectureZoneCount is num) {
    add('${architectureZoneCount.toInt()} zones');
  }
  final approvalType = data['approvalType'];
  if (approvalType is String && approvalType.trim().isNotEmpty) {
    add(approvalType.trim().replaceAll('_', ' '));
  }
  final branchName = data['branchName'];
  if (branchName is String && branchName.trim().isNotEmpty) {
    add(branchName.trim());
  }
  final planSource = data['planSource'];
  if (planSource is String && planSource.trim().isNotEmpty) {
    add(planSource.trim() == 'ai' ? 'AI plan' : 'Heuristic plan');
  }
  final toolRegistrySummary = data['toolRegistrySummary'];
  if (toolRegistrySummary is String && toolRegistrySummary.trim().isNotEmpty) {
    add(toolRegistrySummary.trim());
  }
  final repoContextStrategy = data['repoContextStrategy'];
  if (repoContextStrategy is String && repoContextStrategy.trim().isNotEmpty) {
    add(
      repoContextStrategy.trim() == 'whole_repo_inline'
          ? 'Whole repo inline'
          : 'Expanded repo map',
    );
  } else if (data['wholeRepoEligible'] == true) {
    add('Whole repo inline');
  }
  if (data['openPullRequest'] == true) {
    add(data['mergePullRequest'] == true ? 'PR + merge' : 'Open PR');
  } else if (data['commitChanges'] == true) {
    add('Commit');
  }
  if (data['deployWorkflow'] == true) {
    add('Deploy');
  }
  if (data['riskyOperation'] == true) {
    add('Risky request');
  }
  final pullRequestNumber = data['pullRequestNumber'];
  if (pullRequestNumber is num) {
    add('PR #${pullRequestNumber.toInt()}');
  }
  return items.take(4).toList();
}

String? buildEventInsight(ForgeAgentTaskEvent event) {
  final data = event.data;
  final lines = <String>[];
  final summary = data['summary'];
  if (summary is String && summary.trim().isNotEmpty) {
    lines.add(summary.trim());
  }
  final coverage = data['repoCoverageNotice'];
  if (coverage is String && coverage.trim().isNotEmpty) {
    lines.add(coverage.trim());
  }
  final focusModules = data['focusModules'];
  if (focusModules is List) {
    final modules = focusModules
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .toList();
    if (modules.isNotEmpty) {
      lines.add('Focused modules: ${modules.join(', ')}.');
    }
  }
  final architectureFindings = data['architectureFindings'];
  if (architectureFindings is List) {
    final findings = architectureFindings
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
    if (findings.isNotEmpty) {
      lines.add('Architecture findings: ${findings.join(' | ')}');
    }
  }
  final uncertainties = data['uncertainties'];
  if (uncertainties is List) {
    final pending = uncertainties
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList();
    if (pending.isNotEmpty) {
      lines.add('Still probing: ${pending.join(' | ')}');
    }
  }
  final findings = data['findings'];
  if (findings is List) {
    final items = findings
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .map((item) {
          final filePath = item['filePath'] as String?;
          final line = item['line'] as num?;
          final message = (item['message'] as String?)?.trim() ?? '';
          if (message.isEmpty) {
            return '';
          }
          final prefix = (filePath ?? '').trim().isEmpty
              ? ''
              : '${filePath!.trim()}${line != null ? ':${line.toInt()}' : ''} ';
          return '$prefix$message'.trim();
        })
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
    if (items.isNotEmpty) {
      lines.add('Findings: ${items.join(' | ')}');
    }
  }
  final failureCategory = formatFailureCategoryLabel(
    data['failureCategory'] as String?,
  );
  if (failureCategory.isNotEmpty) {
    lines.add('Failure type: $failureCategory.');
  }
  final failureLocations = data['failureLocations'];
  if (failureLocations is List) {
    final items = failureLocations
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(3)
        .toList();
    if (items.isNotEmpty) {
      lines.add('Exact locations: ${items.join(' | ')}');
    }
  }
  final repairTargetPaths = data['repairTargetPaths'];
  if (repairTargetPaths is List) {
    final items = repairTargetPaths
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList();
    if (items.isNotEmpty) {
      lines.add('Repair scope: ${items.join(', ')}.');
    }
  }
  final workspaceSource = formatWorkspaceSourceLabel(
    data['workspaceSourceOfTruth'] as String?,
  );
  if (workspaceSource.isNotEmpty) {
    lines.add('Source of truth: $workspaceSource.');
  }
  return lines.isEmpty ? null : lines.join('\n');
}

List<ForgeAgentFileVisual> buildFileVisuals({
  required ForgeAgentTask task,
  ForgeRepoExecutionSession? session,
  List<ForgeAgentTaskEvent> events = const <ForgeAgentTaskEvent>[],
}) {
  final visuals = <String, ForgeAgentFileVisual>{};
  final validationFailedPaths = <String>{};
  for (final event in events) {
    if (event.type != 'validation_failed' && event.type != 'tool_failed') {
      continue;
    }
    final raw = event.data['mismatchedPaths'];
    if (raw is List) {
      for (final item in raw) {
        if (item is String && item.trim().isNotEmpty) {
          validationFailedPaths.add(item.trim());
        }
      }
    }
    final failingPaths = event.data['failingPaths'];
    if (failingPaths is List) {
      for (final item in failingPaths) {
        if (item is String && item.trim().isNotEmpty) {
          validationFailedPaths.add(item.trim());
        }
      }
    }
    final findings = event.data['findings'];
    if (findings is List) {
      for (final item in findings.whereType<Map>()) {
        final filePath = item['filePath'];
        if (filePath is String && filePath.trim().isNotEmpty) {
          validationFailedPaths.add(filePath.trim());
        }
      }
    }
    final results = event.data['results'];
    if (results is List) {
      for (final result in results.whereType<Map>()) {
        final findings = result['findings'];
        if (findings is List) {
          for (final item in findings.whereType<Map>()) {
            final filePath = item['filePath'];
            if (filePath is String && filePath.trim().isNotEmpty) {
              validationFailedPaths.add(filePath.trim());
            }
          }
        }
      }
    }
  }

  final actionByPath = <String, String>{};
  if (session != null) {
    for (final edit in session.edits) {
      actionByPath[edit.path] = edit.action;
    }
  }

  for (final path in task.inspectedFiles) {
    visuals[path] = ForgeAgentFileVisual(
      path: path,
      state: ForgeAgentFileVisualState.read,
      label: 'Read',
      action: actionByPath[path],
    );
  }

  for (final path in task.selectedFiles) {
    visuals[path] = ForgeAgentFileVisual(
      path: path,
      state: task.needsApproval
          ? ForgeAgentFileVisualState.readyForReview
          : ForgeAgentFileVisualState.read,
      label: task.needsApproval ? 'Ready for review' : 'Read',
      action: actionByPath[path],
    );
  }

  for (final path in task.filesTouched) {
    final action = actionByPath[path];
    final state = validationFailedPaths.contains(path)
        ? ForgeAgentFileVisualState.validationFailed
        : task.needsApproval
            ? ForgeAgentFileVisualState.readyForReview
            : action == 'create'
                ? ForgeAgentFileVisualState.created
                : ForgeAgentFileVisualState.modified;
    final label = switch (state) {
      ForgeAgentFileVisualState.validationFailed => 'Validation failed',
      ForgeAgentFileVisualState.readyForReview => 'Ready for review',
      ForgeAgentFileVisualState.created => 'New',
      ForgeAgentFileVisualState.modified => 'Modified',
      ForgeAgentFileVisualState.read => 'Read',
    };
    visuals[path] = ForgeAgentFileVisual(
      path: path,
      state: state,
      label: label,
      action: action,
    );
  }

  return visuals.values.toList()
    ..sort((a, b) {
      final stateCompare = fileStatePriority(a.state).compareTo(
        fileStatePriority(b.state),
      );
      if (stateCompare != 0) {
        return stateCompare;
      }
      return a.path.compareTo(b.path);
    });
}

int fileStatePriority(ForgeAgentFileVisualState state) {
  return switch (state) {
    ForgeAgentFileVisualState.validationFailed => 0,
    ForgeAgentFileVisualState.readyForReview => 1,
    ForgeAgentFileVisualState.created => 2,
    ForgeAgentFileVisualState.modified => 3,
    ForgeAgentFileVisualState.read => 4,
  };
}

Color fileStateColor(ForgeAgentFileVisualState state) {
  return switch (state) {
    ForgeAgentFileVisualState.read => ForgePalette.textSecondary,
    ForgeAgentFileVisualState.modified => ForgePalette.glowAccent,
    ForgeAgentFileVisualState.created => ForgePalette.success,
    ForgeAgentFileVisualState.validationFailed => ForgePalette.error,
    ForgeAgentFileVisualState.readyForReview => ForgePalette.warning,
  };
}

IconData fileStateIcon(ForgeAgentFileVisualState state) {
  return switch (state) {
    ForgeAgentFileVisualState.read => Icons.visibility_rounded,
    ForgeAgentFileVisualState.modified => Icons.edit_rounded,
    ForgeAgentFileVisualState.created => Icons.add_circle_outline_rounded,
    ForgeAgentFileVisualState.validationFailed => Icons.error_outline_rounded,
    ForgeAgentFileVisualState.readyForReview => Icons.rate_review_rounded,
  };
}
