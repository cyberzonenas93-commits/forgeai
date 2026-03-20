enum ForgeAgentTaskStatus {
  queued,
  running,
  waitingForInput,
  completed,
  failed,
  cancelled,
}

enum ForgeAgentTaskApprovalType {
  applyChanges,
  commitChanges,
  openPullRequest,
  mergePullRequest,
  deployWorkflow,
  resumeTask,
  riskyOperation,
}

class ForgeAgentTaskFollowUpPlan {
  const ForgeAgentTaskFollowUpPlan({
    this.commitChanges = false,
    this.openPullRequest = false,
    this.mergePullRequest = false,
    this.deployWorkflow = false,
    this.riskyOperation = false,
  });

  final bool commitChanges;
  final bool openPullRequest;
  final bool mergePullRequest;
  final bool deployWorkflow;
  final bool riskyOperation;
}

class ForgeAgentTaskApproval {
  const ForgeAgentTaskApproval({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.status,
    required this.actionLabel,
    required this.cancelLabel,
    required this.payload,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final ForgeAgentTaskApprovalType type;
  final String title;
  final String description;
  final String status;
  final String actionLabel;
  final String cancelLabel;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class ForgeAgentTask {
  const ForgeAgentTask({
    required this.id,
    required this.repoId,
    required this.prompt,
    required this.status,
    required this.phase,
    required this.currentStep,
    required this.deepMode,
    required this.createdAt,
    required this.updatedAt,
    required this.currentPass,
    required this.retryCount,
    required this.selectedFiles,
    required this.inspectedFiles,
    required this.dependencyFiles,
    required this.filesTouched,
    required this.diffCount,
    required this.estimatedTokens,
    required this.followUpPlan,
    required this.metadata,
    this.threadId,
    this.currentFilePath,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.failedAt,
    this.sessionId,
    this.executionSummary,
    this.resultSummary,
    this.errorMessage,
    this.latestEventType,
    this.latestEventMessage,
    this.latestEventAt,
    this.latestValidationError,
    this.pendingApproval,
    this.cancelRequestedAt,
    this.pauseRequestedAt,
  });

  final String id;
  final String repoId;
  final String prompt;
  final String? threadId;
  final String? currentFilePath;
  final ForgeAgentTaskStatus status;
  final String phase;
  final String currentStep;
  final bool deepMode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? failedAt;
  final DateTime? cancelRequestedAt;
  final DateTime? pauseRequestedAt;
  final int currentPass;
  final int retryCount;
  final List<String> selectedFiles;
  final List<String> inspectedFiles;
  final List<String> dependencyFiles;
  final List<String> filesTouched;
  final int diffCount;
  final int estimatedTokens;
  final String? sessionId;
  final String? executionSummary;
  final String? resultSummary;
  final String? errorMessage;
  final String? latestEventType;
  final String? latestEventMessage;
  final DateTime? latestEventAt;
  final String? latestValidationError;
  final ForgeAgentTaskApproval? pendingApproval;
  final ForgeAgentTaskFollowUpPlan followUpPlan;
  final Map<String, dynamic> metadata;

  bool get isActive =>
      status == ForgeAgentTaskStatus.running ||
      status == ForgeAgentTaskStatus.waitingForInput;

  bool get isFinal =>
      status == ForgeAgentTaskStatus.completed ||
      status == ForgeAgentTaskStatus.failed ||
      status == ForgeAgentTaskStatus.cancelled;

  bool get isQueued => status == ForgeAgentTaskStatus.queued;
  bool get isRunning => status == ForgeAgentTaskStatus.running;
  bool get isWaitingForInput => status == ForgeAgentTaskStatus.waitingForInput;
  bool get needsApproval => isWaitingForInput && pendingApproval != null;
}

class ForgeAgentTaskEvent {
  const ForgeAgentTaskEvent({
    required this.id,
    required this.type,
    required this.step,
    required this.message,
    required this.status,
    required this.phase,
    required this.sequence,
    required this.createdAt,
    required this.data,
  });

  final String id;
  final String type;
  final String step;
  final String message;
  final String status;
  final String phase;
  final int sequence;
  final DateTime createdAt;
  final Map<String, dynamic> data;
}
