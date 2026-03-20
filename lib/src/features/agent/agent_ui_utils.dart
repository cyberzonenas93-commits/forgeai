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
  final approvalType = data['approvalType'];
  if (approvalType is String && approvalType.trim().isNotEmpty) {
    add(approvalType.trim().replaceAll('_', ' '));
  }
  final branchName = data['branchName'];
  if (branchName is String && branchName.trim().isNotEmpty) {
    add(branchName.trim());
  }
  final pullRequestNumber = data['pullRequestNumber'];
  if (pullRequestNumber is num) {
    add('PR #${pullRequestNumber.toInt()}');
  }
  return items.take(4).toList();
}

List<ForgeAgentFileVisual> buildFileVisuals({
  required ForgeAgentTask task,
  ForgeRepoExecutionSession? session,
  List<ForgeAgentTaskEvent> events = const <ForgeAgentTaskEvent>[],
}) {
  final visuals = <String, ForgeAgentFileVisual>{};
  final validationFailedPaths = <String>{};
  for (final event in events) {
    if (event.type != 'validation_failed') {
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
