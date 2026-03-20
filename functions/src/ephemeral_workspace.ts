import { existsSync } from 'node:fs';
import {
  access,
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  unlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';

const posix = path.posix;

export interface EphemeralWorkspaceFile {
  path: string;
  content: string;
  isDeleted?: boolean;
}

export interface EphemeralWorkspaceInfo {
  workspacePath: string;
  manifestPath: string;
  fileCount: number;
  createdAtMs: number;
}

export interface LocalRepoWorkspaceInfo extends EphemeralWorkspaceInfo {
  provider: 'github';
  owner: string;
  name: string;
  defaultBranch: string;
  htmlUrl: string | null;
}

export interface EphemeralWorkspaceSearchResult {
  path: string;
  line: number;
  preview: string;
}

export interface LocalWorkspaceValidationCommand {
  id: string;
  name: string;
  category: 'analyze' | 'lint' | 'test' | 'build' | 'bootstrap';
  command: string;
  args: string[];
  summary: string;
}

export interface LocalWorkspaceCommandResult {
  command: LocalWorkspaceValidationCommand;
  status: 'passed' | 'failed' | 'skipped' | 'timed_out';
  durationMs: number;
  output: string;
  exitCode: number | null;
  available: boolean;
}

export interface WorkspaceCommandResult {
  status: 'passed' | 'failed' | 'skipped' | 'timed_out';
  durationMs: number;
  output: string;
  exitCode: number | null;
}

function normalizeRepoPath(value: string) {
  return posix.normalize(value.trim()).replace(/^\/+/, '').replace(/^\.\//, '');
}

function sanitizeWorkspaceSegment(value: string) {
  return value.replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'workspace';
}

async function ensureParentDirectory(filePath: string) {
  await mkdir(path.dirname(filePath), { recursive: true });
}

async function commandExists(command: string) {
  const pathValue = process.env.PATH ?? '';
  const pathSegments = pathValue.split(path.delimiter).filter(Boolean);
  for (const segment of pathSegments) {
    const candidate = path.join(segment, command);
    if (existsSync(candidate)) {
      try {
        await access(candidate);
        return true;
      } catch {
        // try next candidate
      }
    }
  }
  return false;
}

async function runWorkspaceProcess(params: {
  command: string;
  args: string[];
  cwd?: string;
  timeoutMs?: number;
  env?: NodeJS.ProcessEnv;
}) {
  const timeoutMs = params.timeoutMs ?? 240_000;
  const available = await commandExists(params.command);
  if (!available) {
    return {
      status: 'skipped',
      durationMs: 0,
      output: `${params.command} is not available in the runtime environment.`,
      exitCode: null,
    } satisfies WorkspaceCommandResult;
  }

  const startedAt = Date.now();
  const child = spawn(params.command, params.args, {
    cwd: params.cwd,
    env: params.env ?? process.env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    child.kill('SIGKILL');
  }, timeoutMs);

  child.stdout.on('data', chunk => {
    stdout += chunk.toString();
    if (stdout.length > 200_000) {
      stdout = stdout.slice(-200_000);
    }
  });
  child.stderr.on('data', chunk => {
    stderr += chunk.toString();
    if (stderr.length > 200_000) {
      stderr = stderr.slice(-200_000);
    }
  });

  const exitCode = await new Promise<number | null>((resolve, reject) => {
    child.on('error', reject);
    child.on('close', code => resolve(code));
  }).finally(() => clearTimeout(timer));

  return {
    status: timedOut ? 'timed_out' : exitCode === 0 ? 'passed' : 'failed',
    durationMs: Date.now() - startedAt,
    output: `${stdout}\n${stderr}`.trim(),
    exitCode,
  } satisfies WorkspaceCommandResult;
}

function buildGitHubCloneUrl(params: {
  owner: string;
  name: string;
  htmlUrl?: string | null;
}) {
  const trimmed = params.htmlUrl?.trim();
  if (trimmed) {
    return trimmed.endsWith('.git') ? trimmed : `${trimmed}.git`;
  }
  return `https://github.com/${encodeURIComponent(params.owner)}/${encodeURIComponent(params.name)}.git`;
}

function buildGitHttpExtraHeader(token: string) {
  const encoded = Buffer.from(`x-access-token:${token}`, 'utf8').toString('base64');
  return `AUTHORIZATION: basic ${encoded}`;
}

async function configureWorkspaceGitIdentity(workspacePath: string) {
  await runWorkspaceProcess({
    command: 'git',
    args: ['config', 'user.name', 'CodeCatalystAI Agent'],
    cwd: workspacePath,
    timeoutMs: 30_000,
  });
  await runWorkspaceProcess({
    command: 'git',
    args: ['config', 'user.email', 'agent@codecatalystai.local'],
    cwd: workspacePath,
    timeoutMs: 30_000,
  });
}

export async function materializeEphemeralWorkspace(params: {
  ownerId: string;
  repoId: string;
  taskId: string;
  files: EphemeralWorkspaceFile[];
}) {
  const basePath = path.join(
    tmpdir(),
    'forgeai-agent-workspaces',
    sanitizeWorkspaceSegment(params.ownerId),
    sanitizeWorkspaceSegment(params.repoId),
    sanitizeWorkspaceSegment(params.taskId),
  );
  await rm(basePath, { recursive: true, force: true });
  await mkdir(basePath, { recursive: true });

  let fileCount = 0;
  for (const file of params.files) {
    const normalizedPath = normalizeRepoPath(file.path);
    if (!normalizedPath) {
      continue;
    }
    const fullPath = path.join(basePath, normalizedPath);
    if (file.isDeleted === true) {
      await unlink(fullPath).catch(() => undefined);
      continue;
    }
    await ensureParentDirectory(fullPath);
    await writeFile(fullPath, file.content ?? '', 'utf8');
    fileCount += 1;
  }

  const manifestPath = path.join(basePath, '.forgeai-workspace.json');
  const createdAtMs = Date.now();
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        ownerId: params.ownerId,
        repoId: params.repoId,
        taskId: params.taskId,
        fileCount,
        createdAtMs,
      },
      null,
      2,
    ),
    'utf8',
  );

  return {
    workspacePath: basePath,
    manifestPath,
    fileCount,
    createdAtMs,
  } satisfies EphemeralWorkspaceInfo;
}

export async function materializeLocalRepoWorkspace(params: {
  ownerId: string;
  repoId: string;
  taskId: string;
  provider: 'github';
  owner: string;
  name: string;
  defaultBranch: string;
  token: string;
  htmlUrl?: string | null;
}) {
  const taskRoot = path.join(
    tmpdir(),
    'forgeai-local-workspaces',
    sanitizeWorkspaceSegment(params.ownerId),
    sanitizeWorkspaceSegment(params.repoId),
    sanitizeWorkspaceSegment(params.taskId),
  );
  const workspacePath = path.join(taskRoot, 'base');
  await rm(taskRoot, { recursive: true, force: true });
  await mkdir(taskRoot, { recursive: true });

  const cloneUrl = buildGitHubCloneUrl({
    owner: params.owner,
    name: params.name,
    htmlUrl: params.htmlUrl ?? null,
  });
  const cloneResult = await runWorkspaceProcess({
    command: 'git',
    args: [
      '-c',
      `http.extraheader=${buildGitHttpExtraHeader(params.token)}`,
      'clone',
      '--depth',
      '1',
      '--branch',
      params.defaultBranch,
      cloneUrl,
      workspacePath,
    ],
    timeoutMs: 300_000,
  });
  if (cloneResult.status !== 'passed') {
    throw new Error(
      cloneResult.output || `git clone failed for ${params.owner}/${params.name}.`,
    );
  }

  await configureWorkspaceGitIdentity(workspacePath);
  const files = await collectWorkspaceFiles(workspacePath);
  const manifestPath = path.join(taskRoot, '.forgeai-repo-workspace.json');
  const createdAtMs = Date.now();
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        ownerId: params.ownerId,
        repoId: params.repoId,
        taskId: params.taskId,
        provider: params.provider,
        owner: params.owner,
        name: params.name,
        defaultBranch: params.defaultBranch,
        htmlUrl: params.htmlUrl ?? null,
        fileCount: files.length,
        createdAtMs,
      },
      null,
      2,
    ),
    'utf8',
  );
  return {
    workspacePath,
    manifestPath,
    fileCount: files.length,
    createdAtMs,
    provider: params.provider,
    owner: params.owner,
    name: params.name,
    defaultBranch: params.defaultBranch,
    htmlUrl: params.htmlUrl ?? null,
  } satisfies LocalRepoWorkspaceInfo;
}

export async function cloneEphemeralWorkspace(params: {
  sourceWorkspacePath: string;
  targetWorkspacePath: string;
}) {
  await rm(params.targetWorkspacePath, { recursive: true, force: true });
  await mkdir(path.dirname(params.targetWorkspacePath), { recursive: true });
  await cp(params.sourceWorkspacePath, params.targetWorkspacePath, {
    recursive: true,
    force: true,
  });
  const fileCount = (await collectWorkspaceFiles(params.targetWorkspacePath)).length;
  const manifestPath = path.join(params.targetWorkspacePath, '.forgeai-workspace-copy.json');
  const createdAtMs = Date.now();
  await writeFile(
    manifestPath,
    JSON.stringify(
      {
        sourceWorkspacePath: params.sourceWorkspacePath,
        workspacePath: params.targetWorkspacePath,
        fileCount,
        createdAtMs,
      },
      null,
      2,
    ),
    'utf8',
  );
  return {
    workspacePath: params.targetWorkspacePath,
    manifestPath,
    fileCount,
    createdAtMs,
  } satisfies EphemeralWorkspaceInfo;
}

export async function readEphemeralWorkspaceFile(
  workspacePath: string,
  repoPath: string,
) {
  const normalizedPath = normalizeRepoPath(repoPath);
  const fullPath = path.join(workspacePath, normalizedPath);
  return readFile(fullPath, 'utf8');
}

async function collectWorkspaceFiles(rootPath: string, currentPath = rootPath): Promise<string[]> {
  const entries = await readdir(currentPath, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.git')) {
      continue;
    }
    const nextPath = path.join(currentPath, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await collectWorkspaceFiles(rootPath, nextPath)));
      continue;
    }
    files.push(posix.normalize(path.relative(rootPath, nextPath).replace(/\\/g, '/')));
  }
  return files;
}

export async function searchEphemeralWorkspace(params: {
  workspacePath: string;
  query: string;
  maxResults?: number;
}) {
  const normalizedQuery = params.query.trim().toLowerCase();
  if (!normalizedQuery) {
    return [] as EphemeralWorkspaceSearchResult[];
  }
  const maxResults = params.maxResults ?? 20;
  const files = await collectWorkspaceFiles(params.workspacePath);
  const results: EphemeralWorkspaceSearchResult[] = [];
  for (const repoPath of files) {
    if (results.length >= maxResults) {
      break;
    }
    const content = await readEphemeralWorkspaceFile(params.workspacePath, repoPath).catch(
      () => null,
    );
    if (content == null) {
      continue;
    }
    const lines = content.split('\n');
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index] ?? '';
      if (!line.toLowerCase().includes(normalizedQuery)) {
        continue;
      }
      results.push({
        path: repoPath,
        line: index + 1,
        preview: line.trim().slice(0, 240),
      });
      if (results.length >= maxResults) {
        break;
      }
    }
  }
  return results;
}

export async function snapshotEphemeralWorkspace(params: { workspacePath: string }) {
  const files = await collectWorkspaceFiles(params.workspacePath);
  const snapshot = await Promise.all(
    files.map(async repoPath => ({
      path: repoPath,
      content: await readEphemeralWorkspaceFile(params.workspacePath, repoPath),
      isDeleted: false,
    })),
  );
  return snapshot;
}

export async function writeEphemeralWorkspaceFile(params: {
  workspacePath: string;
  repoPath: string;
  content: string;
}) {
  const normalizedPath = normalizeRepoPath(params.repoPath);
  const fullPath = path.join(params.workspacePath, normalizedPath);
  await ensureParentDirectory(fullPath);
  await writeFile(fullPath, params.content, 'utf8');
}

export async function deleteEphemeralWorkspaceFile(params: {
  workspacePath: string;
  repoPath: string;
}) {
  const normalizedPath = normalizeRepoPath(params.repoPath);
  await unlink(path.join(params.workspacePath, normalizedPath)).catch(() => undefined);
}

export async function applyEphemeralWorkspaceEdits(params: {
  workspacePath: string;
  edits: Array<{
    path: string;
    action?: 'create' | 'modify' | 'delete';
    afterContent: string;
  }>;
}) {
  const touchedPaths: string[] = [];
  for (const edit of params.edits) {
    const normalizedPath = normalizeRepoPath(edit.path);
    if (!normalizedPath) {
      continue;
    }
    if (edit.action === 'delete') {
      await deleteEphemeralWorkspaceFile({
        workspacePath: params.workspacePath,
        repoPath: normalizedPath,
      });
      touchedPaths.push(normalizedPath);
      continue;
    }
    await writeEphemeralWorkspaceFile({
      workspacePath: params.workspacePath,
      repoPath: normalizedPath,
      content: edit.afterContent,
    });
    touchedPaths.push(normalizedPath);
  }
  return touchedPaths;
}

export async function workspaceHasPendingChanges(params: { workspacePath: string }) {
  const result = await runWorkspaceProcess({
    command: 'git',
    args: ['status', '--porcelain'],
    cwd: params.workspacePath,
    timeoutMs: 30_000,
  });
  if (result.status !== 'passed') {
    throw new Error(result.output || 'git status failed in the workspace.');
  }
  return result.output.trim().length > 0;
}

export async function checkoutEphemeralWorkspaceBranch(params: {
  workspacePath: string;
  branchName: string;
}) {
  const result = await runWorkspaceProcess({
    command: 'git',
    args: ['checkout', '-B', params.branchName],
    cwd: params.workspacePath,
    timeoutMs: 60_000,
  });
  if (result.status !== 'passed') {
    throw new Error(result.output || `git checkout failed for ${params.branchName}.`);
  }
  return result;
}

export async function commitEphemeralWorkspaceChanges(params: {
  workspacePath: string;
  commitMessage: string;
  allowEmpty?: boolean;
}) {
  const addResult = await runWorkspaceProcess({
    command: 'git',
    args: ['add', '-A'],
    cwd: params.workspacePath,
    timeoutMs: 60_000,
  });
  if (addResult.status !== 'passed') {
    throw new Error(addResult.output || 'git add failed in the workspace.');
  }
  const hasChanges = await workspaceHasPendingChanges({
    workspacePath: params.workspacePath,
  });
  if (!hasChanges && params.allowEmpty !== true) {
    return {
      committed: false,
      summary: 'No local workspace changes were available to commit.',
      output: addResult.output,
    };
  }
  const commitArgs = ['commit', '-m', params.commitMessage];
  if (params.allowEmpty === true) {
    commitArgs.push('--allow-empty');
  }
  const commitResult = await runWorkspaceProcess({
    command: 'git',
    args: commitArgs,
    cwd: params.workspacePath,
    timeoutMs: 120_000,
  });
  if (commitResult.status !== 'passed') {
    throw new Error(commitResult.output || 'git commit failed in the workspace.');
  }
  return {
    committed: true,
    summary: 'Committed local workspace changes.',
    output: commitResult.output,
  };
}

export async function pushEphemeralWorkspaceBranch(params: {
  workspacePath: string;
  token: string;
  provider: 'github';
  branchName: string;
  force?: boolean;
}) {
  const args = [
    '-c',
    `http.extraheader=${buildGitHttpExtraHeader(params.token)}`,
    'push',
    '--set-upstream',
    'origin',
    params.branchName,
  ];
  if (params.force === true) {
    args.splice(3, 0, '--force-with-lease');
  }
  const pushResult = await runWorkspaceProcess({
    command: 'git',
    args,
    cwd: params.workspacePath,
    timeoutMs: 300_000,
  });
  if (pushResult.status !== 'passed') {
    throw new Error(pushResult.output || `git push failed for ${params.branchName}.`);
  }
  return pushResult;
}

export async function readEphemeralWorkspaceHeadRevision(params: { workspacePath: string }) {
  const result = await runWorkspaceProcess({
    command: 'git',
    args: ['rev-parse', 'HEAD'],
    cwd: params.workspacePath,
    timeoutMs: 30_000,
  });
  if (result.status !== 'passed') {
    throw new Error(result.output || 'git rev-parse failed in the workspace.');
  }
  return result.output.trim();
}

export async function cleanupEphemeralWorkspace(workspacePath: string) {
  await rm(workspacePath, { recursive: true, force: true });
}

export async function detectLocalWorkspaceValidationCommands(params: {
  workspacePath: string;
  deepMode: boolean;
}) {
  const commands: LocalWorkspaceValidationCommand[] = [];
  const hasFlutter = await commandExists('flutter');
  const hasDart = await commandExists('dart');
  const hasNpm = await commandExists('npm');
  const hasNpx = await commandExists('npx');

  const hasPubspec = existsSync(path.join(params.workspacePath, 'pubspec.yaml'));
  const hasFlutterPackageConfig = existsSync(
    path.join(params.workspacePath, '.dart_tool', 'package_config.json'),
  );
  const hasPackageJson = existsSync(path.join(params.workspacePath, 'package.json'));
  const hasNodeModules = existsSync(path.join(params.workspacePath, 'node_modules'));
  const hasTests = existsSync(path.join(params.workspacePath, 'test'));
  let packageScripts: Record<string, string> = {};
  if (hasPackageJson) {
    try {
      const raw = await readFile(path.join(params.workspacePath, 'package.json'), 'utf8');
      const parsed = JSON.parse(raw) as { scripts?: Record<string, string> };
      packageScripts = parsed.scripts ?? {};
    } catch {
      packageScripts = {};
    }
  }

  if (hasPubspec && hasFlutter && hasFlutterPackageConfig) {
    commands.push({
      id: 'flutter_analyze',
      name: 'Flutter analyze',
      category: 'analyze',
      command: 'flutter',
      args: ['analyze'],
      summary: 'Run Flutter analyzer against the ephemeral workspace.',
    });
    if (hasTests) {
      commands.push({
        id: 'flutter_test',
        name: 'Flutter test',
        category: 'test',
        command: 'flutter',
        args: ['test'],
        summary: 'Run Flutter tests against the ephemeral workspace.',
      });
    }
  } else if (hasPubspec && hasDart && hasFlutterPackageConfig) {
    commands.push({
      id: 'dart_analyze',
      name: 'Dart analyze',
      category: 'analyze',
      command: 'dart',
      args: ['analyze'],
      summary: 'Run Dart analyzer against the ephemeral workspace.',
    });
    if (hasTests) {
      commands.push({
        id: 'dart_test',
        name: 'Dart test',
        category: 'test',
        command: 'dart',
        args: ['test'],
        summary: 'Run Dart tests against the ephemeral workspace.',
      });
    }
  }

  if (hasPackageJson && hasNpm && hasNodeModules) {
    if (typeof packageScripts.lint === 'string') {
      commands.push({
        id: 'npm_lint',
        name: 'npm lint',
        category: 'lint',
        command: 'npm',
        args: ['run', 'lint'],
        summary: 'Run npm lint in the ephemeral workspace.',
      });
    } else if (hasNpx && existsSync(path.join(params.workspacePath, 'node_modules', '.bin', 'eslint'))) {
      commands.push({
        id: 'eslint',
        name: 'eslint',
        category: 'lint',
        command: 'npx',
        args: ['eslint', '.', '--max-warnings', '0'],
        summary: 'Run eslint in the ephemeral workspace.',
      });
    }
    if (typeof packageScripts.test === 'string' && params.deepMode) {
      commands.push({
        id: 'npm_test',
        name: 'npm test',
        category: 'test',
        command: 'npm',
        args: ['test'],
        summary: 'Run npm test in the ephemeral workspace.',
      });
    }
    if (typeof packageScripts.build === 'string') {
      commands.push({
        id: 'npm_build',
        name: 'npm build',
        category: 'build',
        command: 'npm',
        args: ['run', 'build'],
        summary: 'Run npm build in the ephemeral workspace.',
      });
    }
    if (hasNpx && existsSync(path.join(params.workspacePath, 'node_modules', '.bin', 'tsc'))) {
      commands.push({
        id: 'tsc',
        name: 'tsc',
        category: 'build',
        command: 'npx',
        args: ['tsc', '--noEmit'],
        summary: 'Run TypeScript compile validation in the ephemeral workspace.',
      });
    }
  }

  return commands;
}

export interface OpenShellCommandResult {
  exitCode: number | null;
  stdout: string;
  stderr: string;
  output: string;
  status: 'passed' | 'failed' | 'timed_out' | 'skipped';
  durationMs: number;
}

/**
 * Runs an arbitrary shell command string in the workspace directory.
 *
 * When `sandboxed` is true and Docker is available, the command is wrapped in
 * `docker run --rm --network none -v <workspace>:/workspace -w /workspace node:20-alpine sh -c <cmd>`.
 * When Docker is unavailable or `sandboxed` is false the command runs directly
 * via `sh -c` in the workspace directory.
 *
 * @param params.workspacePath   Absolute path to the cloned workspace.
 * @param params.command         The shell command string to execute.
 * @param params.sandboxed       If true, attempt Docker container isolation (default false).
 * @param params.timeoutMs       Execution timeout in ms (default 60 000, max 300 000).
 * @param params.env             Additional environment variables to inject.
 */
export async function runOpenShellCommand(params: {
  workspacePath: string;
  command: string;
  sandboxed?: boolean;
  timeoutMs?: number;
  env?: NodeJS.ProcessEnv;
}): Promise<OpenShellCommandResult> {
  const rawTimeout = params.timeoutMs ?? 60_000;
  const timeoutMs = Math.min(rawTimeout, 300_000);
  const useSandbox = params.sandboxed === true;

  // Attempt Docker sandbox if requested and available.
  if (useSandbox && (await commandExists('docker'))) {
    const dockerResult = await runWorkspaceProcess({
      command: 'docker',
      args: [
        'run',
        '--rm',
        '--network', 'none',
        '--memory', '512m',
        '--cpus', '1',
        '-v', `${params.workspacePath}:/workspace`,
        '-w', '/workspace',
        'node:20-alpine',
        'sh', '-c', params.command,
      ],
      cwd: params.workspacePath,
      timeoutMs,
      env: { ...process.env, ...params.env },
    });
    const parts = dockerResult.output.split('\n');
    return {
      exitCode: dockerResult.exitCode,
      stdout: dockerResult.output,
      stderr: '',
      output: dockerResult.output,
      status: dockerResult.status,
      durationMs: dockerResult.durationMs,
    };
  }

  // Direct execution path (no Docker or sandbox not requested).
  const startedAt = Date.now();
  const timeoutHandle = { timedOut: false };
  const child = spawn('sh', ['-c', params.command], {
    cwd: params.workspacePath,
    env: { ...process.env, ...params.env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';
  const timer = setTimeout(() => {
    timeoutHandle.timedOut = true;
    child.kill('SIGKILL');
  }, timeoutMs);

  child.stdout.on('data', (chunk: Buffer) => {
    stdout += chunk.toString();
    if (stdout.length > 200_000) stdout = stdout.slice(-200_000);
  });
  child.stderr.on('data', (chunk: Buffer) => {
    stderr += chunk.toString();
    if (stderr.length > 200_000) stderr = stderr.slice(-200_000);
  });

  const exitCode = await new Promise<number | null>((resolve, reject) => {
    child.on('error', reject);
    child.on('close', (code: number | null) => resolve(code));
  }).finally(() => clearTimeout(timer));

  const status = timeoutHandle.timedOut
    ? 'timed_out'
    : exitCode === 0
      ? 'passed'
      : 'failed';

  return {
    exitCode,
    stdout,
    stderr,
    output: `${stdout}\n${stderr}`.trim(),
    status,
    durationMs: Date.now() - startedAt,
  };
}

export async function runLocalWorkspaceCommand(params: {
  workspacePath: string;
  command: LocalWorkspaceValidationCommand;
  timeoutMs?: number;
}) {
  const timeoutMs = params.timeoutMs ?? 240_000;
  const available = await commandExists(params.command.command);
  if (!available) {
    return {
      command: params.command,
      status: 'skipped',
      durationMs: 0,
      output: `${params.command.command} is not available in the runtime environment.`,
      exitCode: null,
      available: false,
    } satisfies LocalWorkspaceCommandResult;
  }

  const startedAt = Date.now();
  const result = await runWorkspaceProcess({
    command: params.command.command,
    args: params.command.args,
    cwd: params.workspacePath,
    timeoutMs,
  });

  return {
    command: params.command,
    status: result.status,
    durationMs: result.durationMs || Date.now() - startedAt,
    output: result.output,
    exitCode: result.exitCode,
    available: true,
  } satisfies LocalWorkspaceCommandResult;
}
