import { HttpsError } from 'firebase-functions/v2/https'

import { OPENAI_LATEST_CHAT_MODEL } from './economics-config'
import { lookupProviderToken, type AiProviderName } from './runtime'
import { callClaude } from './claude_provider'

function providerBaseUrl(provider: AiProviderName) {
  switch (provider) {
    case 'openai':
      return 'https://api.openai.com/v1'
    case 'anthropic':
      return 'https://api.anthropic.com/v1'
    case 'gemini':
      return 'https://generativelanguage.googleapis.com/v1beta'
  }
}

function defaultModelFor(provider: AiProviderName) {
  switch (provider) {
    case 'openai':
      return OPENAI_LATEST_CHAT_MODEL
    case 'anthropic':
      // Default to Sonnet — the balanced model for most agent tasks.
      // Overridden by ANTHROPIC_MODEL env var when set.
      return process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-4-6'
    case 'gemini':
      return process.env.GEMINI_MODEL ?? 'gemini-2.0-flash'
  }
}

function buildOpenAiHeaders(token: string) {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }
}

function buildGeminiHeaders() {
  return {
    'Content-Type': 'application/json',
  }
}

async function fetchJson<T>(input: string, init?: RequestInit): Promise<T> {
  const response = await fetch(input, init)
  if (!response.ok) {
    let message = response.statusText || 'Request failed.'
    try {
      const text = await response.text()
      if (text.trim().length > 0) {
        message = text
      }
    } catch {
      // ignore parser failures
    }
    throw new HttpsError('internal', `AI provider error (${response.status}): ${message}`)
  }
  return (await response.json()) as T
}

export interface ProviderTextCompletionParams {
  provider: AiProviderName
  systemPrompt: string
  userPrompt: string
  maxOutputTokens: number
  temperature?: number
  jsonMode?: boolean
  modelOverride?: string | null
}

export interface ProviderTextCompletionResult {
  provider: AiProviderName
  model: string
  text: string
  /** Actual input token count when available (currently populated for Anthropic). */
  inputTokens?: number
  /** Actual output token count when available (currently populated for Anthropic). */
  outputTokens?: number
}

export async function callProviderTextCompletion(
  params: ProviderTextCompletionParams,
): Promise<ProviderTextCompletionResult> {
  const model = params.modelOverride?.trim() || defaultModelFor(params.provider)
  const temperature = params.temperature ?? 0.1

  // -------------------------------------------------------------------------
  // Anthropic — delegate to the first-class Claude provider module.
  // This uses the Anthropic Messages API and returns real token counts.
  // -------------------------------------------------------------------------
  if (params.provider === 'anthropic') {
    const response = await callClaude(params.userPrompt, {
      model,
      maxTokens: params.maxOutputTokens,
      systemPrompt: params.systemPrompt,
      temperature,
    })
    return {
      provider: params.provider,
      model: response.model,
      text: response.content,
      inputTokens: response.inputTokens,
      outputTokens: response.outputTokens,
    }
  }

  // -------------------------------------------------------------------------
  // OpenAI
  // -------------------------------------------------------------------------
  const tokenInfo = lookupProviderToken(params.provider)
  if (!tokenInfo) {
    throw new HttpsError(
      'failed-precondition',
      `No ${params.provider} token configured for AI completion.`,
    )
  }

  if (params.provider === 'openai') {
    const response = await fetchJson<{
      choices?: Array<{ message?: { content?: string | null } }>
    }>(`${providerBaseUrl(params.provider)}/chat/completions`, {
      method: 'POST',
      headers: buildOpenAiHeaders(tokenInfo.token),
      body: JSON.stringify({
        model,
        temperature,
        max_completion_tokens: params.maxOutputTokens,
        messages: [
          {
            role: 'system',
            content: params.systemPrompt,
          },
          {
            role: 'user',
            content: params.userPrompt,
          },
        ],
        ...(params.jsonMode ? { response_format: { type: 'json_object' } } : {}),
      }),
    })
    return {
      provider: params.provider,
      model,
      text: response.choices?.[0]?.message?.content?.trim() ?? '',
    }
  }

  // -------------------------------------------------------------------------
  // Gemini
  // -------------------------------------------------------------------------
  const response = await fetchJson<{
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>
  }>(
    `${providerBaseUrl(params.provider)}/models/${model}:generateContent?key=${encodeURIComponent(tokenInfo.token)}`,
    {
      method: 'POST',
      headers: buildGeminiHeaders(),
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: params.systemPrompt }] },
        contents: [
          {
            role: 'user',
            parts: [{ text: params.userPrompt }],
          },
        ],
        generationConfig: {
          temperature,
          maxOutputTokens: params.maxOutputTokens,
        },
      }),
    },
  )
  return {
    provider: params.provider,
    model,
    text: response.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? '',
  }
}
