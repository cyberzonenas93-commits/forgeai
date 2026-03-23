import type { AgentValidationFinding } from './agent_validation_tools';

function normalizeOutput(value: string) {
  return value.replace(/\r\n/g, '\n');
}

function normalizeFindingFilePath(value: string | null | undefined) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  return trimmed.replace(/^\.\//, '');
}

export function parseToolOutputFindings(params: {
  output: string;
  source: string;
  limit?: number;
}) {
  const output = normalizeOutput(params.output);
  const limit = params.limit ?? 20;
  const findings: AgentValidationFinding[] = [];
  const lines = output.split('\n');
  const seen = new Set<string>();
  let lastGenericFindingIndex = -1;

  const pushFinding = (finding: AgentValidationFinding) => {
    if (findings.length >= limit) {
      return;
    }
    const normalizedFinding = {
      ...finding,
      filePath: normalizeFindingFilePath(finding.filePath),
      line:
        typeof finding.line === 'number' && finding.line > 0
          ? finding.line
          : null,
      code:
        typeof finding.code === 'string' && finding.code.trim().length > 0
          ? finding.code.trim()
          : null,
      message: finding.message.trim().slice(0, 600),
    } satisfies AgentValidationFinding;
    if (!normalizedFinding.message) {
      return;
    }
    const key = [
      normalizedFinding.source ?? params.source,
      normalizedFinding.severity,
      normalizedFinding.filePath ?? '',
      normalizedFinding.line ?? '',
      normalizedFinding.code ?? '',
      normalizedFinding.message,
    ].join('|');
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    findings.push(normalizedFinding);
    if (!normalizedFinding.filePath) {
      lastGenericFindingIndex = findings.length - 1;
    }
  };

  for (const rawLine of lines) {
    if (findings.length >= limit) {
      break;
    }
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    let match = line.match(/^(.+?):(\d+):(?:(\d+):)?\s*(error|warning)\s*[:\-]?\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[4]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        message: match[5]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s*([A-Z0-9_-]+)?\s*[:\-]?\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[4]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        code: match[5]?.trim() || null,
        message: match[6]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^(.+?):(\d+):(\d+):\s*(error|warning|info)\s*[:\-]?\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[4]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        message: match[5]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^(.+?):(\d+):(\d+):\s*(Error|Warning):\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[4]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        message: match[5]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^(.+?):(\d+):(\d+)\s*-\s*(error|warning)\s*([A-Z0-9_-]+)?\s*[:\-]?\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[4]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        code: match[5]?.trim() || null,
        message: match[6]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^(?:\[\w+\]\s*)?(error|warning)\s+in\s+(.+?)\s+line\s+(\d+)\s*[:\-]?\s*(.+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: match[1]?.toLowerCase() === 'warning' ? 'warning' : 'error',
        filePath: match[2]?.trim(),
        line: Number.parseInt(match[3] ?? '0', 10) || null,
        message: match[4]?.trim() ?? line,
      });
      continue;
    }

    match = line.match(/^FAIL\s+(.+\.[a-z0-9]+)$/i);
    if (match) {
      pushFinding({
        source: params.source,
        severity: 'error',
        filePath: match[1]?.trim(),
        code: 'test_failure',
        message: 'Test file reported a failure.',
      });
      continue;
    }

    match = line.match(/^\s*at\s+(.+?):(\d+):(\d+)\)?$/i);
    if (match && lastGenericFindingIndex >= 0 && lastGenericFindingIndex < findings.length) {
      const current = findings[lastGenericFindingIndex]!;
      if (current.filePath == null) {
        findings[lastGenericFindingIndex] = {
          ...current,
          filePath: normalizeFindingFilePath(match[1]),
          line: Number.parseInt(match[2] ?? '0', 10) || null,
        };
      }
      continue;
    }

    match = line.match(/\b(.+\.[a-z0-9]+):(\d+):(\d+)\b/i);
    if (match && /error|warning|failed|exception/i.test(line)) {
      pushFinding({
        source: params.source,
        severity: /warning/i.test(line) ? 'warning' : 'error',
        filePath: match[1]?.trim(),
        line: Number.parseInt(match[2] ?? '0', 10) || null,
        message: line.slice(0, 600),
      });
      continue;
    }

    if (/error|failed|exception/i.test(line)) {
      pushFinding({
        source: params.source,
        severity: 'error',
        message: line.slice(0, 600),
      });
    }
  }

  return findings;
}

export function summarizeToolOutputFailure(params: {
  commandLabel: string;
  output: string;
  fallbackMessage?: string;
}) {
  const findings = parseToolOutputFindings({
    output: params.output,
    source: params.commandLabel,
    limit: 4,
  });
  if (findings.length === 0) {
    return params.fallbackMessage ?? `${params.commandLabel} failed.`;
  }
  return `${params.commandLabel} failed. ${findings
    .map(finding => {
      const location =
        typeof finding.filePath === 'string' && finding.filePath.trim().length > 0
          ? `${finding.filePath}${finding.line != null ? `:${finding.line}` : ''}`
          : null;
      return location ? `${location} ${finding.message}` : finding.message;
    })
    .join(' | ')}`;
}
