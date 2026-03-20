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
  exports: string[];
  symbolHints: string[];
  role: string;
  architectureHints: string[];
  isEntrypoint: boolean;
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

function extractExports(content: string) {
  const matches = [
    ...content.matchAll(/^\s*export\s+(?:class|function|const|let|var|enum|interface|type)\s+([A-Za-z_][A-Za-z0-9_]*)/gm),
    ...content.matchAll(/^\s*(?:class|enum|interface|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)/gm),
    ...content.matchAll(/^\s*(?:Future<[^>]+>\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm),
  ];
  return dedupe(
    matches
        .map(match => match[1] ?? '')
        .filter(value => value.length >= 3 && !STOP_WORDS.has(value.toLowerCase())),
    12,
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

function inferArchitectureHints(params: {
  path: string;
  content: string;
  imports: string[];
  symbols: string[];
  role: string;
}) {
  const hints = <string[]>[];
  const lowerPath = params.path.toLowerCase();
  const lowerContent = params.content.toLowerCase();
  const joinedImports = params.imports.join(' ').toLowerCase();
  const joinedSymbols = params.symbols.join(' ').toLowerCase();

  if (
    lowerPath.endsWith('/main.dart') ||
    lowerPath.endsWith('/main.ts') ||
    lowerPath.endsWith('/main.js') ||
    lowerPath.endsWith('/app.dart') ||
    lowerPath.endsWith('/app.ts') ||
    lowerPath.endsWith('/app.js')
  ) {
    hints.push('entrypoint');
  }
  if (lowerPath.includes('/auth/') || lowerContent.includes('firebaseauth') || joinedSymbols.includes('auth')) {
    hints.push('auth');
  }
  if (lowerPath.includes('/repo') || lowerPath.includes('/repository') || lowerContent.includes('repository')) {
    hints.push('repository');
  }
  if (lowerPath.includes('/service') || lowerContent.includes('service')) {
    hints.push('service');
  }
  if (lowerPath.includes('/widget') || lowerPath.includes('/screen') || params.role.includes('widget')) {
    hints.push('ui');
  }
  if (lowerPath.startsWith('functions/src/') || lowerContent.includes('oncall(') || lowerContent.includes('firebase-functions')) {
    hints.push('backend');
  }
  if (lowerPath.includes('/routes/') || lowerPath.includes('/navigation/') || lowerContent.includes('navigator')) {
    hints.push('navigation');
  }
  if (lowerPath.includes('/model') || lowerPath.includes('/entities') || lowerPath.includes('/domain/')) {
    hints.push('domain');
  }
  if (lowerPath.startsWith('.github/workflows/') || lowerPath.endsWith('.yml') || lowerPath.endsWith('.yaml')) {
    hints.push('workflow');
  }
  if (joinedImports.includes('flutter') || lowerContent.includes('statelesswidget') || lowerContent.includes('statefulwidget')) {
    hints.push('flutter');
  }
  if (lowerContent.includes('firestore') || lowerContent.includes('firebase')) {
    hints.push('firebase');
  }

  return dedupe(hints, 8);
}

function inferEntrypoint(path: string, hints: string[], role: string) {
  const lowerPath = path.toLowerCase();
  return (
    hints.includes('entrypoint') ||
    lowerPath === 'readme.md' ||
    lowerPath.startsWith('.github/workflows/') ||
    lowerPath.endsWith('/main.dart') ||
    lowerPath.endsWith('/main.ts') ||
    lowerPath.endsWith('/main.js') ||
    lowerPath.endsWith('/app.dart') ||
    lowerPath.endsWith('/app.ts') ||
    lowerPath.endsWith('/app.js') ||
    role === 'workflow/config'
  );
}

function buildSummary(path: string, content: string, language: string | null | undefined) {
  const role = classifyRole(path, content);
  const imports = extractImports(content).slice(0, 3);
  const symbols = extractSymbols(content).slice(0, 3);
  const architectureHints = inferArchitectureHints({
    path,
    content,
    imports,
    symbols,
    role,
  }).slice(0, 2);
  const parts = [
    `${path} is a ${role}`,
    language ? `written in ${language}` : '',
    imports.length > 0 ? `that depends on ${imports.join(', ')}` : '',
    symbols.length > 0 ? `and exposes ${symbols.join(', ')}` : '',
    architectureHints.length > 0 ? `with architecture hints ${architectureHints.join(', ')}` : '',
  ].filter(Boolean);
  return truncate(normalizeWhitespace(parts.join(' ')), 260);
}

export function generateFileSummary(input: FileSummaryInput): FileSummaryResult {
  const rawContent = input.content ?? input.contentPreview ?? '';
  const normalizedContent = normalizeWhitespace(rawContent);
  const imports = extractImports(rawContent);
  const symbolHints = extractSymbols(rawContent);
  const exports = extractExports(rawContent);
  const role = classifyRole(input.path, rawContent);
  const architectureHints = inferArchitectureHints({
    path: input.path,
    content: rawContent,
    imports,
    symbols: symbolHints,
    role,
  });
  const isEntrypoint = inferEntrypoint(input.path, architectureHints, role);
  const keywords = dedupe(
    [
      ...pathTokens(input.path),
      ...(input.language ? [input.language.toLowerCase()] : []),
      ...imports.flatMap(value => value.toLowerCase().split(/[^a-z0-9]+/)),
      ...exports.map(value => value.toLowerCase()),
      ...symbolHints.map(value => value.toLowerCase()),
      ...architectureHints,
      role.toLowerCase(),
      ...extractContentKeywords(normalizedContent),
    ],
    24,
  );
  const summary = buildSummary(input.path, rawContent, input.language);
  const embeddingText = truncate(
    normalizeWhitespace(
      [
        input.path,
        summary,
        keywords.join(' '),
        imports.join(' '),
        exports.join(' '),
        symbolHints.join(' '),
        role,
        architectureHints.join(' '),
        isEntrypoint ? 'entrypoint' : '',
      ]
        .filter(Boolean)
        .join(' '),
    ),
    1200,
  );
  return {
    summary,
    keywords,
    imports,
    exports,
    symbolHints,
    role,
    architectureHints,
    isEntrypoint,
    embeddingText,
  };
}
