import '../../auth/domain/auth_account.dart';

enum ForgeAiProvider { openai, anthropic, gemini }

enum ForgeGitActionType {
  createBranch,
  commit,
  openPullRequest,
  mergePullRequest,
}

enum ForgeCheckActionType { runTests, runLint, buildProject }

class ForgeFileDocument {
  const ForgeFileDocument({
    required this.repoId,
    required this.path,
    required this.language,
    required this.content,
    required this.originalContent,
    required this.updatedAt,
    this.sha,
  });

  final String repoId;
  final String path;
  final String language;
  final String content;
  final String originalContent;
  final DateTime? updatedAt;
  final String? sha;

  bool get hasUnsavedChanges => content != originalContent;

  ForgeFileDocument copyWith({
    String? repoId,
    String? path,
    String? language,
    String? content,
    String? originalContent,
    DateTime? updatedAt,
    String? sha,
  }) {
    return ForgeFileDocument(
      repoId: repoId ?? this.repoId,
      path: path ?? this.path,
      language: language ?? this.language,
      content: content ?? this.content,
      originalContent: originalContent ?? this.originalContent,
      updatedAt: updatedAt ?? this.updatedAt,
      sha: sha ?? this.sha,
    );
  }
}

class ForgeDiffLine {
  const ForgeDiffLine({
    required this.prefix,
    required this.line,
    required this.isAddition,
  });

  final String prefix;
  final String line;
  final bool isAddition;
}

class ForgeChangeRequest {
  const ForgeChangeRequest({
    required this.id,
    required this.repoId,
    required this.filePath,
    required this.provider,
    required this.prompt,
    required this.status,
    required this.summary,
    required this.beforeContent,
    required this.afterContent,
    required this.diffLines,
    required this.estimatedTokens,
  });

  final String id;
  final String repoId;
  final String filePath;
  final ForgeAiProvider provider;
  final String prompt;
  final String status;
  final String summary;
  final String beforeContent;
  final String afterContent;
  final List<ForgeDiffLine> diffLines;
  final int estimatedTokens;

  bool get isDraft => status == 'draft';
}

class ForgeConnectRepositoryDraft {
  const ForgeConnectRepositoryDraft({
    required this.provider,
    required this.repository,
    required this.defaultBranch,
    this.accessToken,
    this.apiBaseUrl,
  });

  final String provider;
  final String repository;
  final String defaultBranch;
  final String? accessToken;
  final String? apiBaseUrl;
}

class ForgeAvailableRepository {
  const ForgeAvailableRepository({
    required this.provider,
    required this.owner,
    required this.name,
    required this.fullName,
    required this.defaultBranch,
    required this.isPrivate,
    this.description,
    this.htmlUrl,
  });

  final String provider;
  final String owner;
  final String name;
  final String fullName;
  final String defaultBranch;
  final bool isPrivate;
  final String? description;
  final String? htmlUrl;
}

class ForgeGitDraft {
  const ForgeGitDraft({
    required this.branchName,
    required this.commitMessage,
    required this.pullRequestTitle,
    required this.pullRequestDescription,
    this.mergeMethod = 'merge',
  });

  final String branchName;
  final String commitMessage;
  final String pullRequestTitle;
  final String pullRequestDescription;
  final String mergeMethod;

  ForgeGitDraft copyWith({
    String? branchName,
    String? commitMessage,
    String? pullRequestTitle,
    String? pullRequestDescription,
    String? mergeMethod,
  }) {
    return ForgeGitDraft(
      branchName: branchName ?? this.branchName,
      commitMessage: commitMessage ?? this.commitMessage,
      pullRequestTitle: pullRequestTitle ?? this.pullRequestTitle,
      pullRequestDescription:
          pullRequestDescription ?? this.pullRequestDescription,
      mergeMethod: mergeMethod ?? this.mergeMethod,
    );
  }
}


class ForgePromptMessage {
  const ForgePromptMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String role; // user | assistant
  final String text;
  final DateTime createdAt;
}

class ForgePromptThread {
  const ForgePromptThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.repoId,
  });

  final String id;
  final String title;
  final String? repoId;
  final List<ForgePromptMessage> messages;
  final DateTime updatedAt;

  ForgePromptThread copyWith({
    String? title,
    String? repoId,
    List<ForgePromptMessage>? messages,
    DateTime? updatedAt,
    bool clearRepoId = false,
  }) {
    return ForgePromptThread(
      id: id,
      title: title ?? this.title,
      repoId: clearRepoId ? null : (repoId ?? this.repoId),
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}


class ForgePromptMediaAttachment {
  const ForgePromptMediaAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.dataBase64,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final String dataBase64;
}

class ForgePromptAgentTrace {
  const ForgePromptAgentTrace({
    required this.threadId,
    required this.recordedAt,
    required this.steps,
    required this.inspectedFiles,
    required this.proposedEditFiles,
    required this.plannedEdits,
    required this.summary,
  });

  final String threadId;
  final DateTime recordedAt;
  final List<String> steps;
  final List<String> inspectedFiles;
  final List<String> proposedEditFiles;
  final List<ForgePromptPlannedEdit> plannedEdits;
  final String summary;
}

class ForgePromptPlannedEdit {
  const ForgePromptPlannedEdit({
    required this.path,
    required this.action,
    required this.rationale,
  });

  final String path;
  final String action;
  final String rationale;
}

class ForgeAskRepoResult {
  const ForgeAskRepoResult({
    required this.reply,
    this.inspectedFiles = const <String>[],
    this.plannedEdits = const <ForgePromptPlannedEdit>[],
  });

  final String reply;
  final List<String> inspectedFiles;
  final List<ForgePromptPlannedEdit> plannedEdits;
}

class ForgeCreateAiProjectResult {
  const ForgeCreateAiProjectResult({
    required this.repoId,
    required this.fullName,
    required this.defaultBranch,
    required this.fileCount,
    this.htmlUrl,
    this.syncStatus,
  });

  final String repoId;
  final String fullName;
  final String defaultBranch;
  final int fileCount;
  final String? htmlUrl;
  final String? syncStatus;

  static ForgeCreateAiProjectResult fromCallableData(
    Map<Object?, Object?> data,
  ) {
    final repoId = data['repoId'] as String?;
    final fullName = data['fullName'] as String?;
    if (repoId == null || repoId.isEmpty) {
      throw const FormatException('createProjectRepository: missing repoId');
    }
    final fc = data['fileCount'];
    final fileCount = fc is int
        ? fc
        : fc is num
            ? fc.toInt()
            : 0;
    final rawBranch = (data['defaultBranch'] as String?)?.trim() ?? '';
    return ForgeCreateAiProjectResult(
      repoId: repoId,
      fullName: fullName ?? repoId,
      defaultBranch: rawBranch.isNotEmpty ? rawBranch : 'main',
      fileCount: fileCount,
      htmlUrl: data['htmlUrl'] as String?,
      syncStatus: data['syncStatus'] as String?,
    );
  }
}

class ForgeAccountProfile {
  const ForgeAccountProfile({
    required this.account,
    required this.connectedProviders,
  });

  final AuthAccount account;
  final List<String> connectedProviders;
}
