/**
 * claude_provider.ts
 *
 * First-class Anthropic Claude provider module for ForgeAI.
 *
 * This implementation uses the Anthropic REST API directly via fetch, matching
 * the pattern used throughout the codebase. The `@anthropic-ai/sdk` package is
 * listed in package.json — after running `npm install` you can replace the
 * fetch call below with:
 *
 *   import Anthropic from '@anthropic-ai/sdk'
 *   const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY })
 *   const msg = await client.messages.create({ ... })
 *
 * The interface exported here remains identical either way.
 */

import { loadLocalEnvFiles } from './runtime'

// ---------------------------------------------------------------------------
// Model constants
// ---------------------------------------------------------------------------

/** Best reasoning / complex multi-file planning. ~$15/$75 per 1M in/out tokens. */
export const CLAUDE_OPUS_MODEL = 'claude-opus-4-6'

/** Best balance of quality and speed for diff generation. ~$3/$15 per 1M in/out. */
export const CLAUDE_SONNET_MODEL = 'claude-sonnet-4-6'

/** Fast and cheap for validation, repair, and simple tasks. ~$0.25/$1.25 per 1M. */
export const CLAUDE_HAIKU_MODEL = 'claude-haiku-4-5-20251001'

/** Default model when no specific model is requested. */
export const CLAUDE_DEFAULT_MODEL = CLAUDE_SONNET_MODEL

/** All supported Claude model identifiers. */
export const CLAUDE_MODELS = [
  CLAUDE_OPUS_MODEL,
  CLAUDE_SONNET_MODEL,
  CLAUDE_HAIKU_MODEL,
] as const

export type ClaudeModel = (typeof CLAUDE_MODELS)[number]

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ClaudeCallOptions {
  /** Model to use. Defaults to claude-sonnet-4-6. */
  model?: string
  /** Maximum output tokens. Defaults to 4096. */
  maxTokens?: number
  /** System prompt content. */
  systemPrompt?: string
  /** Sampling temperature (0–1). Defaults to 0.1. */
  temperature?: number
}

export interface ClaudeResponse {
  content: string
  inputTokens: number
  outputTokens: number
  model: string
  stopReason: string
}

export interface ClaudeError {
  error: true
  message: string
  statusCode?: number
}

// ---------------------------------------------------------------------------
// Raw API response types (Anthropic Messages API)
// ---------------------------------------------------------------------------

interface AnthropicMessageResponse {
  id: string
  type: string
  role: string
  content: Array<{ type: string; text?: string }>
  model: string
  stop_reason: string | null
  usage: {
    input_tokens: number
    output_tokens: number
  }
}

interface AnthropicErrorResponse {
  type: 'error'
  error: {
    type: string
    message: string
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

const ANTHROPIC_API_BASE = 'https://api.anthropic.com/v1'
const ANTHROPIC_VERSION = '2023-06-01'
const DEFAULT_MAX_TOKENS = 4096
const DEFAULT_TEMPERATURE = 0.1

function getApiKey(): string {
  loadLocalEnvFiles()
  const key = process.env.ANTHROPIC_API_KEY?.trim()
  if (!key) {
    throw new Error(
      'ANTHROPIC_API_KEY is not set. ' +
      'Set it in functions/.env for local dev or via Firebase Secret Manager for production.',
    )
  }
  return key
}

function buildHeaders(apiKey: string) {
  return {
    'x-api-key': apiKey,
    'anthropic-version': ANTHROPIC_VERSION,
    'content-type': 'application/json',
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Call Claude using the Anthropic Messages API.
 *
 * @param prompt   The user-turn message to send.
 * @param options  Optional overrides for model, token limits, and system prompt.
 * @returns        Structured response with content, token counts, and stop reason.
 * @throws         Error if the API key is missing or the API returns a non-2xx response.
 *
 * @example
 * ```ts
 * const response = await callClaude('Explain this diff:\n' + diff, {
 *   model: CLAUDE_SONNET_MODEL,
 *   systemPrompt: 'You are a senior software engineer reviewing a code change.',
 *   maxTokens: 1024,
 * })
 * console.log(response.content)
 * console.log(`Used ${response.inputTokens} input + ${response.outputTokens} output tokens`)
 * ```
 */
export async function callClaude(
  prompt: string,
  options: ClaudeCallOptions = {},
): Promise<ClaudeResponse> {
  const apiKey = getApiKey()
  const model = options.model?.trim() || CLAUDE_DEFAULT_MODEL
  const maxTokens = options.maxTokens ?? DEFAULT_MAX_TOKENS
  const temperature = options.temperature ?? DEFAULT_TEMPERATURE

  const body: Record<string, unknown> = {
    model,
    max_tokens: maxTokens,
    temperature,
    messages: [{ role: 'user', content: prompt }],
  }

  if (options.systemPrompt?.trim()) {
    body.system = options.systemPrompt.trim()
  }

  const response = await fetch(`${ANTHROPIC_API_BASE}/messages`, {
    method: 'POST',
    headers: buildHeaders(apiKey),
    body: JSON.stringify(body),
  })

  if (!response.ok) {
    let errorMessage = `Anthropic API error ${response.status}: ${response.statusText}`
    try {
      const errBody = (await response.json()) as Partial<AnthropicErrorResponse>
      if (errBody?.error?.message) {
        errorMessage = `Anthropic API error ${response.status}: ${errBody.error.message}`
      }
    } catch {
      // ignore parse failure, use the status-based message
    }
    const err = new Error(errorMessage) as Error & { statusCode?: number }
    err.statusCode = response.status
    throw err
  }

  const data = (await response.json()) as AnthropicMessageResponse

  const content = data.content
    .filter(block => block.type === 'text')
    .map(block => block.text ?? '')
    .join('')
    .trim()

  return {
    content,
    inputTokens: data.usage?.input_tokens ?? 0,
    outputTokens: data.usage?.output_tokens ?? 0,
    model: data.model ?? model,
    stopReason: data.stop_reason ?? 'end_turn',
  }
}

/**
 * Convenience wrapper for planning stages — uses claude-opus-4-6 by default.
 * Best for complex multi-step reasoning, architecture planning, and deep analysis.
 */
export async function callClaudeForPlanning(
  prompt: string,
  options: Omit<ClaudeCallOptions, 'model'> & { model?: string } = {},
): Promise<ClaudeResponse> {
  return callClaude(prompt, { model: CLAUDE_OPUS_MODEL, ...options })
}

/**
 * Convenience wrapper for diff generation — uses claude-sonnet-4-6 by default.
 * Optimal balance of quality and latency for code editing tasks.
 */
export async function callClaudeForEditing(
  prompt: string,
  options: Omit<ClaudeCallOptions, 'model'> & { model?: string } = {},
): Promise<ClaudeResponse> {
  return callClaude(prompt, { model: CLAUDE_SONNET_MODEL, ...options })
}

/**
 * Convenience wrapper for validation / repair — uses claude-haiku-4-5-20251001 by default.
 * Fast and cost-efficient for structured output verification and quick fixes.
 */
export async function callClaudeForValidation(
  prompt: string,
  options: Omit<ClaudeCallOptions, 'model'> & { model?: string } = {},
): Promise<ClaudeResponse> {
  return callClaude(prompt, { model: CLAUDE_HAIKU_MODEL, ...options })
}

/**
 * Returns true if the given model string is one of the known Claude models.
 */
export function isClaudeModel(model: string): model is ClaudeModel {
  return (CLAUDE_MODELS as readonly string[]).includes(model)
}
