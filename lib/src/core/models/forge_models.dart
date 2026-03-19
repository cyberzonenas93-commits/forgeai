enum ForgeSection {
  dashboard,
  repositories,
  editor,
  checks,
  wallet,
  activity,
  settings,
}

enum GitProviderKind { github, gitlab }

enum ReviewLineKind { added, removed, unchanged }

enum CheckRunStatus { queued, running, passed, failed }

enum CheckRunType { tests, lint, build }

enum ActivityKind {
  auth,
  ai,
  repo,
  commit,
  pullRequest,
  checks,
  wallet,
  security,
}

enum AiProviderKind { openai, anthropic, gemini }

class ConnectedRepository {
  const ConnectedRepository({
    required this.id,
    required this.owner,
    required this.name,
    required this.provider,
    required this.defaultBranch,
    required this.headBranch,
    required this.description,
    required this.lastActivityLabel,
    required this.isPrivate,
    required this.pendingReviews,
    required this.pendingChecks,
  });

  final String id;
  final String owner;
  final String name;
  final GitProviderKind provider;
  final String defaultBranch;
  final String headBranch;
  final String description;
  final String lastActivityLabel;
  final bool isPrivate;
  final int pendingReviews;
  final int pendingChecks;

  String get fullName => '$owner/$name';
}

class CodeFile {
  const CodeFile({
    required this.path,
    required this.language,
    required this.content,
    required this.lastUpdatedLabel,
    required this.changeCount,
  });

  final String path;
  final String language;
  final String content;
  final String lastUpdatedLabel;
  final int changeCount;
}

class ReviewLine {
  const ReviewLine({
    required this.kind,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final ReviewLineKind kind;
  final String content;
  final int? oldLineNumber;
  final int? newLineNumber;
}

class CheckRun {
  const CheckRun({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.branch,
    required this.summary,
    required this.startedAtLabel,
    required this.recentLogs,
  });

  final String id;
  final String name;
  final CheckRunType type;
  final CheckRunStatus status;
  final String branch;
  final String summary;
  final String startedAtLabel;
  final List<String> recentLogs;
}

class TokenWallet {
  const TokenWallet({
    required this.balance,
    required this.monthlyLimit,
    required this.monthlyUsed,
    required this.pendingReservation,
  });

  final int balance;
  final int monthlyLimit;
  final int monthlyUsed;
  final int pendingReservation;

  int get monthlyRemaining => monthlyLimit - monthlyUsed;
}

class TokenLedgerEntry {
  const TokenLedgerEntry({
    required this.id,
    required this.label,
    required this.detail,
    required this.delta,
    required this.timestampLabel,
  });

  final String id;
  final String label;
  final String detail;
  final int delta;
  final String timestampLabel;
}

class ActivityRecord {
  const ActivityRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.timestampLabel,
  });

  final String id;
  final ActivityKind kind;
  final String title;
  final String description;
  final String timestampLabel;
}

class AiTaskPreset {
  const AiTaskPreset({
    required this.id,
    required this.title,
    required this.description,
    required this.provider,
    required this.estimatedTokens,
  });

  final String id;
  final String title;
  final String description;
  final AiProviderKind provider;
  final int estimatedTokens;
}

class GitActionDraft {
  const GitActionDraft({
    required this.branchName,
    required this.commitMessage,
    required this.pullRequestTitle,
    required this.pullRequestDescription,
  });

  final String branchName;
  final String commitMessage;
  final String pullRequestTitle;
  final String pullRequestDescription;
}
