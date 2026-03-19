import '../../../shared/forge_models.dart';
import 'forge_workspace_entities.dart';

/// Default wallet until backend snapshot arrives. Backend grants unlimited only to allowlisted email.
const _defaultWallet = ForgeTokenWallet(
  planName: 'Free',
  balance: 0,
  monthlyAllowance: 0,
  spentThisWeek: 0,
  nextReset: 'Not set',
  currencySymbol: 'tokens',
);

class ForgeWorkspaceState {
  const ForgeWorkspaceState({
    this.isBootstrapping = false,
    this.isSyncing = false,
    this.isSavingFile = false,
    this.isRunningAi = false,
    this.isSubmittingGitAction = false,
    this.isRunningCheck = false,
    this.isConnectingRepository = false,
    this.repositories = const <ForgeRepository>[],
    this.connections = const <ForgeConnection>[],
    this.files = const <ForgeFileNode>[],
    this.activities = const <ForgeActivityEntry>[],
    this.checks = const <ForgeCheckRun>[],
    this.repoWorkflows = const <ForgeRepoWorkflow>[],
    this.tokenLogs = const <ForgeTokenLog>[],
    this.promptThreads = const <ForgePromptThread>[],
    this.selectedPromptThreadId,
    this.isPromptLoading = false,
    this.promptStatusThreadId,
    this.promptStatusText,
    this.promptStatusSteps = const <String>[],
    this.promptLastAgentTrace,
    this.promptDangerMode = true,
    this.repoExecutionDeepMode = false,
    this.notificationPreferences = ForgeNotificationPreferences.defaults,
    this.wallet = _defaultWallet,
    this.selectedRepository,
    this.selectedBranch,
    this.selectedFile,
    this.currentDocument,
    this.currentChangeRequest,
    this.currentExecutionSession,
    this.errorMessage,
  });

  final bool isBootstrapping;
  final bool isSyncing;
  final bool isSavingFile;
  final bool isRunningAi;
  final bool isSubmittingGitAction;
  final bool isRunningCheck;
  final bool isConnectingRepository;
  final List<ForgeRepository> repositories;
  final List<ForgeConnection> connections;
  final List<ForgeFileNode> files;
  final List<ForgeActivityEntry> activities;
  final List<ForgeCheckRun> checks;
  final List<ForgeRepoWorkflow> repoWorkflows;
  final List<ForgeTokenLog> tokenLogs;
  final List<ForgePromptThread> promptThreads;
  final String? selectedPromptThreadId;
  final bool isPromptLoading;
  final String? promptStatusThreadId;
  final String? promptStatusText;
  final List<String> promptStatusSteps;
  final ForgePromptAgentTrace? promptLastAgentTrace;
  final bool promptDangerMode;
  final bool repoExecutionDeepMode;
  final ForgeNotificationPreferences notificationPreferences;
  final ForgeTokenWallet wallet;
  final ForgeRepository? selectedRepository;
  final String? selectedBranch;
  final ForgeFileNode? selectedFile;
  final ForgeFileDocument? currentDocument;
  final ForgeChangeRequest? currentChangeRequest;
  final ForgeRepoExecutionSession? currentExecutionSession;
  final String? errorMessage;

  bool get hasRepositories => repositories.isNotEmpty;
  bool get hasConnections => connections.isNotEmpty;
  bool get hasSelection => selectedRepository != null;
  bool get hasOpenFile => currentDocument != null;

  ForgeWorkspaceState copyWith({
    bool? isBootstrapping,
    bool? isSyncing,
    bool? isSavingFile,
    bool? isRunningAi,
    bool? isSubmittingGitAction,
    bool? isRunningCheck,
    bool? isConnectingRepository,
    List<ForgeRepository>? repositories,
    List<ForgeConnection>? connections,
    List<ForgeFileNode>? files,
    List<ForgeActivityEntry>? activities,
    List<ForgeCheckRun>? checks,
    List<ForgeRepoWorkflow>? repoWorkflows,
    List<ForgeTokenLog>? tokenLogs,
    List<ForgePromptThread>? promptThreads,
    String? selectedPromptThreadId,
    bool? isPromptLoading,
    String? promptStatusThreadId,
    String? promptStatusText,
    List<String>? promptStatusSteps,
    ForgePromptAgentTrace? promptLastAgentTrace,
    bool? promptDangerMode,
    bool? repoExecutionDeepMode,
    ForgeNotificationPreferences? notificationPreferences,
    ForgeTokenWallet? wallet,
    ForgeRepository? selectedRepository,
    String? selectedBranch,
    ForgeFileNode? selectedFile,
    ForgeFileDocument? currentDocument,
    ForgeChangeRequest? currentChangeRequest,
    ForgeRepoExecutionSession? currentExecutionSession,
    String? errorMessage,
    bool clearRepository = false,
    bool clearSelectedBranch = false,
    bool clearSelectedFile = false,
    bool clearCurrentDocument = false,
    bool clearCurrentChangeRequest = false,
    bool clearCurrentExecutionSession = false,
    bool clearError = false,
    bool clearSelectedPromptThread = false,
    bool clearPromptStatus = false,
  }) {
    return ForgeWorkspaceState(
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isSyncing: isSyncing ?? this.isSyncing,
      isSavingFile: isSavingFile ?? this.isSavingFile,
      isRunningAi: isRunningAi ?? this.isRunningAi,
      isSubmittingGitAction:
          isSubmittingGitAction ?? this.isSubmittingGitAction,
      isRunningCheck: isRunningCheck ?? this.isRunningCheck,
      isConnectingRepository:
          isConnectingRepository ?? this.isConnectingRepository,
      repositories: repositories ?? this.repositories,
      connections: connections ?? this.connections,
      files: files ?? this.files,
      activities: activities ?? this.activities,
      checks: checks ?? this.checks,
      repoWorkflows: repoWorkflows ?? this.repoWorkflows,
      tokenLogs: tokenLogs ?? this.tokenLogs,
      promptThreads: promptThreads ?? this.promptThreads,
      selectedPromptThreadId: clearSelectedPromptThread
          ? null
          : (selectedPromptThreadId ?? this.selectedPromptThreadId),
      isPromptLoading: isPromptLoading ?? this.isPromptLoading,
      promptStatusThreadId: clearPromptStatus
          ? null
          : (promptStatusThreadId ?? this.promptStatusThreadId),
      promptStatusText: clearPromptStatus
          ? null
          : (promptStatusText ?? this.promptStatusText),
      promptStatusSteps: clearPromptStatus
          ? const <String>[]
          : (promptStatusSteps ?? this.promptStatusSteps),
      promptLastAgentTrace: promptLastAgentTrace ?? this.promptLastAgentTrace,
      promptDangerMode: promptDangerMode ?? this.promptDangerMode,
      repoExecutionDeepMode:
          repoExecutionDeepMode ?? this.repoExecutionDeepMode,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      wallet: wallet ?? this.wallet,
      selectedRepository: clearRepository
          ? null
          : (selectedRepository ?? this.selectedRepository),
      selectedBranch: clearSelectedBranch
          ? null
          : (selectedBranch ?? this.selectedBranch),
      selectedFile: clearSelectedFile
          ? null
          : (selectedFile ?? this.selectedFile),
      currentDocument: clearCurrentDocument
          ? null
          : (currentDocument ?? this.currentDocument),
      currentChangeRequest: clearCurrentChangeRequest
          ? null
          : (currentChangeRequest ?? this.currentChangeRequest),
      currentExecutionSession: clearCurrentExecutionSession
          ? null
          : (currentExecutionSession ?? this.currentExecutionSession),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static const ForgeWorkspaceState empty = ForgeWorkspaceState();
}
