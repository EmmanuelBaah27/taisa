import Anthropic from '@anthropic-ai/sdk';

export const anthropicClient = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

export const MODEL = 'claude-sonnet-4-6';
export const MOCK_AI = process.env.MOCK_AI === 'true';

// Parses Anthropic SDK error messages (format: "${status} ${json}") into user-friendly codes.
export function parseAnthropicError(error: any): { code: string; message: string } {
  const raw: string = error?.message ?? '';
  const spaceIdx = raw.indexOf(' ');
  if (spaceIdx > -1) {
    try {
      const body = JSON.parse(raw.slice(spaceIdx + 1));
      const msg: string = body?.error?.message ?? '';
      const type: string = body?.error?.type ?? '';
      if (msg.toLowerCase().includes('credit') || msg.toLowerCase().includes('billing')) {
        return { code: 'BILLING_ERROR', message: 'Anthropic API credits exhausted — top up at console.anthropic.com.' };
      }
      if (type === 'rate_limit_error') {
        return { code: 'AI_RATE_LIMITED', message: 'AI rate limit hit. Try again in a moment.' };
      }
      if (type === 'authentication_error') {
        return { code: 'AI_AUTH_ERROR', message: 'Anthropic API key is invalid or expired.' };
      }
      if (type === 'overloaded_error') {
        return { code: 'AI_OVERLOADED', message: 'Anthropic API is overloaded. Try again shortly.' };
      }
      if (msg) return { code: 'AI_ERROR', message: msg };
    } catch {
      // JSON parse failed, fall through
    }
  }
  return { code: 'AI_ERROR', message: raw || 'AI service error' };
}

export interface ClaudeCallOptions {
  system: string;
  userMessage: string;
  temperature?: number;
  maxTokens?: number;
}

export async function callClaude(options: ClaudeCallOptions): Promise<string> {
  const { system, userMessage, temperature = 0.3, maxTokens = 4096 } = options;

  const response = await anthropicClient.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    system,
    messages: [{ role: 'user', content: userMessage }],
  });

  const content = response.content[0];
  if (content.type !== 'text') throw new Error('Unexpected response type from Claude');
  return content.text;
}

export async function callClaudeJson<T>(options: ClaudeCallOptions): Promise<T> {
  const text = await callClaude(options);

  // Strip markdown code fences if present
  const cleaned = text.replace(/^```(?:json)?\s*/m, '').replace(/\s*```\s*$/m, '').trim();

  try {
    return JSON.parse(cleaned) as T;
  } catch (firstError) {
    // Retry with explicit instruction
    console.warn('JSON parse failed, retrying with explicit schema reminder');
    const retryText = await callClaude({
      ...options,
      userMessage: options.userMessage + '\n\nIMPORTANT: Your response must be ONLY valid JSON with no markdown, no explanation, no code fences.',
    });
    const retrycleaned = retryText.replace(/^```(?:json)?\s*/m, '').replace(/\s*```\s*$/m, '').trim();
    return JSON.parse(retrycleaned) as T;
  }
}

export default anthropicClient;
