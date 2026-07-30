// Provider-agnostic AI layer — one callAI() interface, three HTTPS backends.
// Plain fetch (no SDKs): each provider's chat-completion API is a single
// JSON POST, and a dependency per provider isn't worth it for that.

export type AiProviderName = 'OPENAI' | 'ANTHROPIC' | 'GEMINI';

export interface ChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface CallAiParams {
  provider: AiProviderName;
  apiKey: string;
  model: string;
  systemPrompt: string;
  userPrompt: string;
  history?: ChatTurn[];
}

export interface CallAiResult {
  text: string;
  usage: { inputTokens: number; outputTokens: number };
}

// A slow/hung provider must never hang the caller.
const TIMEOUT_MS = 30_000;

// Each provider's error JSON nests its human-readable message differently —
// this is the one field worth surfacing (short, safe text like "model X not
// found"), never the full payload (which can include account/billing detail).
function extractProviderMessage(bodyText: string): string | null {
  try {
    const body = JSON.parse(bodyText);
    return body?.error?.message ?? null;
  } catch {
    return null;
  }
}

// Maps a failed provider call to a clear, safe-to-show message. Model-name
// and other request-shape problems (4xx, not auth/rate-limit) surface the
// provider's own message — e.g. "model X is no longer available" — so the
// user can fix it by typing a different model, instead of a generic failure.
function providerError(provider: string, status: number, bodyText: string): Error {
  const providerMessage = extractProviderMessage(bodyText);
  let message: string;
  if (status === 401 || status === 403) message = `${provider} rejected the API key — check that it's correct and active.`;
  else if (status === 429) message = `${provider} rate-limited this request — wait a moment and try again.`;
  else if (status >= 500) message = `${provider} is currently unavailable — try again shortly.`;
  else if (providerMessage) message = `${provider}: ${providerMessage}`;
  else message = `${provider} request failed (${status}).`;
  console.error(`AI provider error [${provider} ${status}]: ${bodyText.slice(0, 500)}`);
  return Object.assign(new Error(message), { status: status === 401 || status === 403 ? 401 : status === 429 ? 429 : 502 });
}

async function fetchWithTimeout(url: string, init: RequestInit, provider: string): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch (err: any) {
    if (err?.name === 'TimeoutError' || err?.name === 'AbortError') {
      throw Object.assign(new Error(`${provider} took too long to respond — try again.`), { status: 504 });
    }
    throw Object.assign(new Error(`Could not reach ${provider} — check your connection and try again.`), { status: 502 });
  }
}

export async function callAI(params: CallAiParams): Promise<CallAiResult> {
  switch (params.provider) {
    case 'OPENAI': return callOpenAI(params);
    case 'ANTHROPIC': return callAnthropic(params);
    case 'GEMINI': return callGemini(params);
    default: throw Object.assign(new Error('Unknown AI provider'), { status: 400 });
  }
}

async function callOpenAI({ apiKey, model, systemPrompt, userPrompt, history }: CallAiParams): Promise<CallAiResult> {
  const messages = [
    { role: 'system', content: systemPrompt },
    ...(history ?? []).map(h => ({ role: h.role, content: h.content })),
    { role: 'user', content: userPrompt },
  ];
  const res = await fetchWithTimeout('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, messages }),
  }, 'OpenAI');

  const bodyText = await res.text();
  if (!res.ok) throw providerError('OpenAI', res.status, bodyText);
  const data = JSON.parse(bodyText);
  return {
    text: data.choices?.[0]?.message?.content ?? '',
    usage: {
      inputTokens: data.usage?.prompt_tokens ?? 0,
      outputTokens: data.usage?.completion_tokens ?? 0,
    },
  };
}

async function callAnthropic({ apiKey, model, systemPrompt, userPrompt, history }: CallAiParams): Promise<CallAiResult> {
  const messages = [
    ...(history ?? []).map(h => ({ role: h.role, content: h.content })),
    { role: 'user', content: userPrompt },
  ];
  const res = await fetchWithTimeout('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({ model, system: systemPrompt, messages, max_tokens: 1024 }),
  }, 'Anthropic');

  const bodyText = await res.text();
  if (!res.ok) throw providerError('Anthropic', res.status, bodyText);
  const data = JSON.parse(bodyText);
  return {
    text: (data.content ?? []).map((c: any) => c.text ?? '').join(''),
    usage: {
      inputTokens: data.usage?.input_tokens ?? 0,
      outputTokens: data.usage?.output_tokens ?? 0,
    },
  };
}

async function callGemini({ apiKey, model, systemPrompt, userPrompt, history }: CallAiParams): Promise<CallAiResult> {
  const contents = [
    ...(history ?? []).map(h => ({ role: h.role === 'assistant' ? 'model' : 'user', parts: [{ text: h.content }] })),
    { role: 'user', parts: [{ text: userPrompt }] },
  ];
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const res = await fetchWithTimeout(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contents, systemInstruction: { parts: [{ text: systemPrompt }] } }),
  }, 'Gemini');

  const bodyText = await res.text();
  if (!res.ok) throw providerError('Gemini', res.status, bodyText);
  const data = JSON.parse(bodyText);
  return {
    text: (data.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? '').join(''),
    usage: {
      inputTokens: data.usageMetadata?.promptTokenCount ?? 0,
      outputTokens: data.usageMetadata?.candidatesTokenCount ?? 0,
    },
  };
}

// Sensible cheap default model per provider — pre-filled in the UI, always
// user-editable (provider model catalogs move faster than this file does).
// Checked 2026-07-30: gpt-4.1-mini remains available via the OpenAI API
// (only retired from the ChatGPT product UI). The entire Gemini 2.5 Flash
// family (both gemini-2.5-flash and gemini-2.5-flash-lite) has been
// returning 404 "no longer available" since 2026-07-09 — a Google-side
// incident well ahead of their documented Oct 16 2026 shutdown date,
// reported broadly on Google's AI Developer forum, not specific to any one
// key/account. Defaulting to the 3.x family instead: gemini-3.5-flash-lite
// is the current stable, budget-tier Flash model.
export const DEFAULT_MODEL: Record<AiProviderName, string> = {
  OPENAI: 'gpt-4.1-mini',
  ANTHROPIC: 'claude-haiku-4-5-20251001',
  GEMINI: 'gemini-3.5-flash-lite',
};
