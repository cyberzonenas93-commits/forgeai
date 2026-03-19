/// Quick Prompt-tab commands that run GitHub Actions (or install workflow files)
/// without opening the tools sheet — similar to typing a short command in chat.
enum PromptGitQuickCommand {
  /// Dispatches `.github/workflows/run-app.yml` (or [workflow] field in tools).
  runAppViaGit,

  /// Dispatches `.github/workflows/deploy-functions.yml`.
  deployFunctionsViaGit,

  /// Commits a starter `deploy-functions.yml` into the repo.
  installDeployWorkflow,

  /// Commits starter `run-app.yml` into the repo.
  installRunAppWorkflow,
}

/// Returns a command if [message] is a dedicated Git quick command (whole message).
PromptGitQuickCommand? matchPromptGitQuickCommand(String message) {
  final t = message.trim().toLowerCase();
  if (t.isEmpty) return null;

  bool has(String s) => t.contains(s);

  if (has('install deploy') ||
      has('add deploy-functions') ||
      has('install deploy-functions') ||
      has('add deploy workflow') ||
      has('install deploy workflow')) {
    return PromptGitQuickCommand.installDeployWorkflow;
  }
  if (has('install run-app') ||
      has('install run app') ||
      has('add run-app') ||
      has('add run app workflow')) {
    return PromptGitQuickCommand.installRunAppWorkflow;
  }

  final deployFunctions = (has('deploy') &&
          (has('function') || has('firebase') || has('cloud function'))) ||
      has('firebase deploy') ||
      t == 'deploy functions' ||
      t == 'deploy firebase' ||
      t == 'deploy cloud functions';

  if (deployFunctions) {
    return PromptGitQuickCommand.deployFunctionsViaGit;
  }

  if (has('run app via git') ||
      has('run via git') ||
      has('run through git') ||
      has('run the app via git') ||
      (has('run the app') && has('git')) ||
      has('run-app.yml') ||
      has('dispatch run-app') ||
      has('trigger run-app') ||
      (has('github action') && has('run')) ||
      (has('workflow') && has('run app'))) {
    return PromptGitQuickCommand.runAppViaGit;
  }

  if (t == 'run the app' || t == 'run app' || t == 'run my app') {
    return PromptGitQuickCommand.runAppViaGit;
  }

  return null;
}
