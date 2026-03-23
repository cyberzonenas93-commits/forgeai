import path from 'node:path';

const posix = path.posix;

export type AgentValidationToolKind =
  | 'workspace_consistency'
  | 'static_repo_validation'
  | 'workspace_command'
  | 'ci_workflow';

export type AgentValidationToolStatus =
  | 'passed'
  | 'failed'
  | 'skipped'
  | 'timed_out';

export interface AgentValidationFinding {
  message: string;
  severity: 'error' | 'warning';
  filePath?: string | null;
  line?: number | null;
  code?: string | null;
  source?: string | null;
}

export interface AgentValidationToolResult {
  id: string;
  kind: AgentValidationToolKind;
  name: string;
  status: AgentValidationToolStatus;
  summary: string;
  durationMs: number;
  findings: AgentValidationFinding[];
  workflowName?: string | null;
  workflowPath?: string | null;
  workflowCategory?: string | null;
  checkRunId?: string | null;
  logsUrl?: string | null;
  branchName?: string | null;
  executed: boolean;
}

export interface AgentValidationWorkflow {
  id: number | string;
  name: string;
  path: string;
}

export interface PlannedValidationWorkflow {
  id: string;
  kind: 'ci_workflow';
  name: string;
  workflowName: string;
  workflowPath: string;
  workflowCategory: string;
}

export interface RepoWorkingCopyFile {
  path: string;
  content: string;
  baseContent: string;
  isDeleted: boolean;
}

const JS_IMPORT_EXTENSIONS = [
  '.ts',
  '.tsx',
  '.js',
  '.jsx',
  '.mts',
  '.cts',
  '.mjs',
  '.cjs',
  '.json',
] as const;

function normalizeRepoPath(value: string) {
  return posix.normalize(value.trim()).replace(/^\/+/, '').replace(/^\.\//, '');
}

function detectPromptHints(prompt: string) {
  const normalized = prompt.toLowerCase();
  return {
    test: /\b(test|tests|spec|assert|integration|unit)\b/.test(normalized),
    lint: /\b(lint|analy(z|s)e|format|style|static)\b/.test(normalized),
    build: /\b(build|compile|bundle|typecheck|release)\b/.test(normalized),
    ui: /\b(ui|screen|widget|layout|flutter)\b/.test(normalized),
  };
}

function classifyWorkflowCategory(workflow: AgentValidationWorkflow) {
  const label = `${workflow.name} ${workflow.path}`.toLowerCase();
  if (
    label.includes('deploy') ||
    label.includes('release') ||
    label.includes('publish') ||
    label.includes('ship')
  ) {
    return {
      excluded: true,
      category: 'deploy',
    };
  }
  if (label.includes('lint') || label.includes('analy') || label.includes('format')) {
    return {
      excluded: false,
      category: 'lint',
    };
  }
  if (
    label.includes('test') ||
    label.includes('spec') ||
    label.includes('integration') ||
    label.includes('unit')
  ) {
    return {
      excluded: false,
      category: 'test',
    };
  }
  if (
    label.includes('build') ||
    label.includes('compile') ||
    label.includes('bundle') ||
    label.includes('typecheck')
  ) {
    return {
      excluded: false,
      category: 'build',
    };
  }
  if (label.includes('ci') || label.includes('verify') || label.includes('validation')) {
    return {
      excluded: false,
      category: 'ci',
    };
  }
  return {
    excluded: false,
    category: 'other',
  };
}

export function buildValidationWorkflowPlan(params: {
  workflows: AgentValidationWorkflow[];
  prompt: string;
  deepMode: boolean;
}) {
  const hints = detectPromptHints(params.prompt);
  const limit = params.deepMode ? 3 : 2;
  const ranked = params.workflows
    .map(workflow => {
      const classification = classifyWorkflowCategory(workflow);
      const label = `${workflow.name} ${workflow.path}`.toLowerCase();
      let score = 0;
      switch (classification.category) {
        case 'test':
          score += 16;
          break;
        case 'lint':
          score += 14;
          break;
        case 'build':
          score += 12;
          break;
        case 'ci':
          score += 10;
          break;
        default:
          score += 4;
          break;
      }
      if (hints.test && classification.category === 'test') {
        score += 8;
      }
      if (hints.lint && classification.category === 'lint') {
        score += 7;
      }
      if (hints.build && classification.category === 'build') {
        score += 7;
      }
      if (hints.ui && (label.includes('flutter') || label.includes('analy'))) {
        score += 4;
      }
      return {
        workflow,
        category: classification.category,
        excluded: classification.excluded,
        score,
      };
    })
    .filter(item => item.excluded !== true)
    .sort(
      (a, b) =>
        b.score - a.score ||
        a.workflow.path.localeCompare(b.workflow.path),
    );

  const selected: Array<typeof ranked[number]> = [];
  const seenCategories = new Set<string>();
  for (const candidate of ranked) {
    if (selected.length >= limit) {
      break;
    }
    if (candidate.category !== 'other' && seenCategories.has(candidate.category)) {
      continue;
    }
    selected.push(candidate);
    seenCategories.add(candidate.category);
  }
  if (selected.length === 0 && ranked.length > 0) {
    selected.push(ranked[0]);
  }
  return selected.map(candidate => ({
    id: `workflow:${candidate.workflow.path}`,
    kind: 'ci_workflow' as const,
    name: candidate.workflow.name,
    workflowName: candidate.workflow.path,
    workflowPath: candidate.workflow.path,
    workflowCategory: candidate.category,
  }));
}

function lineFromIndex(text: string, index: number) {
  if (index <= 0) {
    return 1;
  }
  return text.slice(0, index).split('\n').length;
}

function parseDartPackageName(files: RepoWorkingCopyFile[]) {
  const pubspec = files.find(file => normalizeRepoPath(file.path) === 'pubspec.yaml');
  if (!pubspec) {
    return null;
  }
  const match = pubspec.content.match(/^\s*name\s*:\s*([a-zA-Z0-9_\-]+)/m);
  return match?.[1] ?? null;
}

function resolveRelativeImportTarget(
  sourcePath: string,
  importPath: string,
  existingPaths: Set<string>,
  extensions: readonly string[],
) {
  const sourceDir = posix.dirname(sourcePath);
  const basePath = normalizeRepoPath(posix.join(sourceDir, importPath));
  const candidates = new Set<string>([basePath]);
  if (!posix.extname(basePath)) {
    for (const extension of extensions) {
      candidates.add(`${basePath}${extension}`);
      candidates.add(posix.join(basePath, `index${extension}`));
    }
  }
  for (const candidate of candidates) {
    if (existingPaths.has(candidate)) {
      return candidate;
    }
  }
  return null;
}

function collectRelativeImportFindings(params: {
  file: RepoWorkingCopyFile;
  existingPaths: Set<string>;
  dartPackageName: string | null;
}) {
  const findings: AgentValidationFinding[] = [];
  const pushFinding = (finding: AgentValidationFinding) => {
    if (findings.length >= 20) {
      return;
    }
    findings.push(finding);
  };
  const extension = posix.extname(params.file.path).toLowerCase();
  const lines = params.file.content.split('\n');
  if (
    extension === '.ts' ||
    extension === '.tsx' ||
    extension === '.js' ||
    extension === '.jsx' ||
    extension === '.mts' ||
    extension === '.cts' ||
    extension === '.mjs' ||
    extension === '.cjs'
  ) {
    const jsImportPattern =
      /\b(?:import|export)\s+(?:[^'"]+?\s+from\s+)?['"]([^'"]+)['"]|require\(\s*['"]([^'"]+)['"]\s*\)|import\(\s*['"]([^'"]+)['"]\s*\)/;
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index] ?? '';
      const match = line.match(jsImportPattern);
      const specifier = match?.[1] ?? match?.[2] ?? match?.[3] ?? null;
      if (!specifier || !specifier.startsWith('.')) {
        continue;
      }
      const resolved = resolveRelativeImportTarget(
        params.file.path,
        specifier,
        params.existingPaths,
        JS_IMPORT_EXTENSIONS,
      );
      if (!resolved) {
        pushFinding({
          severity: 'error',
          filePath: params.file.path,
          line: index + 1,
          code: 'missing_import',
          source: 'static_repo_validation',
          message: `Cannot resolve local import "${specifier}".`,
        });
      }
    }
    return findings;
  }
  if (extension !== '.dart') {
    return findings;
  }

  const dartImportPattern = /\b(?:import|export|part)\s+['"]([^'"]+)['"]/;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index] ?? '';
    const match = line.match(dartImportPattern);
    const specifier = match?.[1] ?? null;
    if (!specifier) {
      continue;
    }
    if (specifier.startsWith('.')) {
      const resolved = resolveRelativeImportTarget(
        params.file.path,
        specifier,
        params.existingPaths,
        ['.dart'],
      );
      if (!resolved) {
        pushFinding({
          severity: 'error',
          filePath: params.file.path,
          line: index + 1,
          code: 'missing_import',
          source: 'static_repo_validation',
          message: `Cannot resolve local Dart import "${specifier}".`,
        });
      }
      continue;
    }
    if (
      params.dartPackageName &&
      specifier.startsWith(`package:${params.dartPackageName}/`)
    ) {
      const packagePath = `lib/${specifier.slice(`package:${params.dartPackageName}/`.length)}`;
      const normalized = normalizeRepoPath(packagePath);
      if (!params.existingPaths.has(normalized)) {
        pushFinding({
          severity: 'error',
          filePath: params.file.path,
          line: index + 1,
          code: 'missing_import',
          source: 'static_repo_validation',
          message: `Cannot resolve package import "${specifier}" inside this repository.`,
        });
      }
    }
  }
  return findings;
}

export function runStaticRepoValidations(params: {
  files: RepoWorkingCopyFile[];
}) {
  const startedAt = Date.now();
  const existingPaths = new Set<string>();
  for (const file of params.files) {
    if (!file.isDeleted) {
      existingPaths.add(normalizeRepoPath(file.path));
    }
  }
  const changedFiles = params.files.filter(
    file => !file.isDeleted && file.content !== file.baseContent,
  );
  const findings: AgentValidationFinding[] = [];
  const seenKeys = new Set<string>();
  const dartPackageName = parseDartPackageName(params.files);
  const pushFinding = (finding: AgentValidationFinding) => {
    const key = `${finding.filePath ?? ''}:${finding.line ?? ''}:${finding.code ?? ''}:${finding.message}`;
    if (seenKeys.has(key) || findings.length >= 24) {
      return;
    }
    seenKeys.add(key);
    findings.push(finding);
  };

  for (const file of changedFiles) {
    const normalizedPath = normalizeRepoPath(file.path);
    const conflictMatch = /^(<<<<<<<|=======|>>>>>>>)/m.exec(file.content);
    if (conflictMatch?.index != null) {
      pushFinding({
        severity: 'error',
        filePath: normalizedPath,
        line: lineFromIndex(file.content, conflictMatch.index),
        code: 'merge_conflict_marker',
        source: 'static_repo_validation',
        message: 'Unresolved merge conflict markers are still present in the file.',
      });
    }
    if (posix.extname(normalizedPath).toLowerCase() === '.json') {
      try {
        JSON.parse(file.content);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Invalid JSON.';
        const positionMatch = message.match(/position\s+(\d+)/i);
        const position = positionMatch ? Number.parseInt(positionMatch[1] ?? '', 10) : null;
        pushFinding({
          severity: 'error',
          filePath: normalizedPath,
          line:
            position != null && Number.isFinite(position)
              ? lineFromIndex(file.content, position)
              : null,
          code: 'invalid_json',
          source: 'static_repo_validation',
          message,
        });
      }
    }
    for (const finding of collectRelativeImportFindings({
      file: {
        ...file,
        path: normalizedPath,
      },
      existingPaths,
      dartPackageName,
    })) {
      pushFinding(finding);
    }
  }

  const affectedFiles = new Set(
    findings
      .map(finding => (typeof finding.filePath === 'string' ? finding.filePath.trim() : ''))
      .filter(value => value.length > 0),
  );
  const status: AgentValidationToolStatus = findings.length > 0 ? 'failed' : 'passed';
  const summary =
    findings.length > 0
      ? `Static repo validation found ${findings.length} issue${findings.length === 1 ? '' : 's'} across ${affectedFiles.size || 1} file${affectedFiles.size === 1 ? '' : 's'}.`
      : `Static repo validation passed for ${changedFiles.length} changed file${changedFiles.length === 1 ? '' : 's'}.`;
  return {
    id: 'static_repo_validation',
    kind: 'static_repo_validation' as const,
    name: 'Static repo validation',
    status,
    summary,
    durationMs: Date.now() - startedAt,
    findings,
    executed: true,
  } satisfies AgentValidationToolResult;
}

export function summarizeValidationToolResults(results: AgentValidationToolResult[]) {
  if (results.length === 0) {
    return 'No validation tools ran.';
  }
  const failures = results.filter(result => result.status === 'failed' || result.status === 'timed_out');
  if (failures.length === 0) {
    const passed = results.filter(result => result.status === 'passed');
    const skipped = results.filter(result => result.status === 'skipped');
    const parts: string[] = [];
    if (passed.length > 0) {
      parts.push(
        `Passed: ${passed.map(result => result.name).join(', ')}.`,
      );
    }
    if (skipped.length > 0) {
      parts.push(
        skipped
          .map(result => `${result.name} skipped: ${result.summary}`)
          .join(' '),
      );
    }
    return parts.join(' ').trim() || 'Validation passed.';
  }
  return failures
    .map(result => {
      const findingSummary = result.findings
        .slice(0, 4)
        .map(finding => {
          const location =
            typeof finding.filePath === 'string' && finding.filePath.trim().length > 0
              ? `${finding.filePath}${finding.line != null ? `:${finding.line}` : ''}`
              : null;
          return location != null ? `${location} ${finding.message}` : finding.message;
        })
        .join(' | ');
      return `${result.name}: ${findingSummary || result.summary}`;
    })
    .join('\n');
}

export function serializeValidationToolResults(results: AgentValidationToolResult[]) {
  return results.map(result => ({
    id: result.id,
    kind: result.kind,
    name: result.name,
    status: result.status,
    summary: result.summary,
    durationMs: result.durationMs,
    findings: result.findings.map(finding => ({
      message: finding.message,
      severity: finding.severity,
      filePath: finding.filePath ?? null,
      line: finding.line ?? null,
      code: finding.code ?? null,
      source: finding.source ?? null,
    })),
    workflowName: result.workflowName ?? null,
    workflowPath: result.workflowPath ?? null,
    workflowCategory: result.workflowCategory ?? null,
    checkRunId: result.checkRunId ?? null,
    logsUrl: result.logsUrl ?? null,
    branchName: result.branchName ?? null,
    executed: result.executed,
  }));
}
