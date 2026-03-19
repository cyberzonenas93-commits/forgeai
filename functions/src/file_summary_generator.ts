export interface FileSummaryInput {
  path: string;
  language?: string | null;
  content?: string | null;
  contentPreview?: string | null;
  type?: string | null;
}

export interface FileSummaryResult {
  summary: string;
  keywords: string[];
  imports: string[];
  symbolHints: string[];
  embeddingText: string;
}

const STOP_WORDS = new Set([
  'the',
  'and',
  'for',
  'with',
  'from',
  'into',
  'that',
  'this',
  'then',
  'when',
  'your',
  'repo',
  'code',
  'file',
  'files',
  'true',
  'false',
  'null',
  'void',
  'final',
  'const',
  'class',
  'return',
  'async',
  'await',
  'static',
]);

function normalizeWhitespace(value: string) {
  return value.replace(/\s+/g, ' ').trim();
}

function truncate(value: string, maxChars: number) {
  if (value.length <= maxChars) {
    return value;
  }
  return `${value.slice(0, maxChars - 1)}...`;
}

function dedupe(values: string[], limit: number) {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    const value = raw.trim();
    if (!value) {
      continue;
    }
    const key = value.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(value);
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}

function pathTokens(path: string) {
  return path
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map(part => part.trim())
    .filter(part => part.length >= 3 && !STOP_WORDS.has(part));
}

function extractImports(content: string) {
  const matches = [
    ...content.matchAll(/^\s*import\s+['"]([^'"]+)['"]/gm),
    ...content.matchAll(/^\s*export\s+.*from\s+['"]([^'"]+)['"]/gm),
    ...content.matchAll(/^\s*const\s+.*=\s*require\(\s*['"]([^'"]+)['"]\s*\)/gm),
    ...content.matchAll(/^\s*import\s+([A-Za-z0-9_.]+)/gm),
  ];
  return dedupe(
    matches
      .map(match => match[1] ?? '')
      .map(value => value.trim())
      .filter(value => value.length >= 2),
    12,
  );
}

function extractSymbols(content: string) {
  const matches = [
    ...content.matchAll(/\bclass\s+([A-Z][A-Za-z0-9_]+)/g),
    ...content.matchAll(/\benum\s+([A-Z][A-Za-z0-9_]+)/g),
    ...content.matchAll(/\b(?:function|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)/g),
    ...content.matchAll(/\b(?:const|final|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=/g),
    ...content.matchAll(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\(/g),
  ];
  return dedupe(
    matches
      .map(match => match[1] ?? '')
      .filter(value => value.length >= 3 && !STOP_WORDS.has(value.toLowerCase())),
    16,
  );
}

function extractContentKeywords(content: string) {
  const tokens = content
    .toLowerCase()
    .split(/[^a-z0-9_./-]+/)
    .map(part => part.trim())
    .filter(part => part.length >= 4 && !STOP_WORDS.has(part));
  return dedupe(tokens, 18);
}

function classifyRole(path: string, content: string) {
  const lowerPath = path.toLowerCase();
  const lowerContent = content.toLowerCase();
  if (lowerPath.endsWith('_screen.dart') || lowerPath.includes('/screens/')) {
    return 'screen';
  }
  if (lowerPath.endsWith('_widget.dart') || lowerPath.includes('/widgets/')) {
    return 'widget';
  }
  if (lowerPath.endsWith('_service.dart') || lowerPath.includes('/services/')) {
    return 'service';
  }
  if (lowerPath.endsWith('_controller.dart') || lowerPath.includes('/controllers/')) {
    return 'controller';
  }
  if (lowerPath.endsWith('_repository.dart') || lowerPath.includes('/repositories/')) {
    return 'repository';
  }
  if (lowerPath.endsWith('.yml') || lowerPath.endsWith('.yaml')) {
    return 'workflow/config';
  }
  if (lowerPath.endsWith('.md')) {
    return 'documentation';
  }
  if (lowerContent.includes('oncall(')) {
    return 'backend callable';
  }
  if (lowerContent.includes('statelesswidget') || lowerContent.includes('statefulwidget')) {
    return 'flutter widget';
  }
  if (lowerContent.includes('class ') && lowerContent.includes('repository')) {
    return 'data access module';
  }
  return 'source file';
}

function buildSummary(path: string, content: string, language: string | null | undefined) {
  const role = classifyRole(path, content);
  const imports = extractImports(content).slice(0, 3);
  const symbols = extractSymbols(content).slice(0, 3);
  const parts = [
    `${path} is a ${role}`,
    language ? `written in ${language}` : '',
    imports.length > 0 ? `that depends on ${imports.join(', ')}` : '',
    symbols.length > 0 ? `and exposes ${symbols.join(', ')}` : '',
  ].filter(Boolean);
  return truncate(normalizeWhitespace(parts.join(' ')), 260);
}

export function generateFileSummary(input: FileSummaryInput): FileSummaryResult {
  const content = normalizeWhitespace(input.content ?? input.contentPreview ?? '');
  const imports = extractImports(content);
  const symbolHints = extractSymbols(content);
  const keywords = dedupe(
    [
      ...pathTokens(input.path),
      ...(input.language ? [input.language.toLowerCase()] : []),
      ...imports.flatMap(value => value.toLowerCase().split(/[^a-z0-9]+/)),
      ...symbolHints.map(value => value.toLowerCase()),
      ...extractContentKeywords(content),
    ],
    24,
  );
  const summary = buildSummary(input.path, content, input.language);
  const embeddingText = truncate(
    normalizeWhitespace(
      [input.path, summary, keywords.join(' '), imports.join(' '), symbolHints.join(' ')]
        .filter(Boolean)
        .join(' '),
    ),
    1200,
  );
  return {
    summary,
    keywords,
    imports,
    symbolHints,
    embeddingText,
  };
}
