/**
 * Credential proxy for container isolation.
 * Containers connect here instead of directly to the Anthropic API.
 * The proxy injects real credentials so containers never see them.
 *
 * Two auth modes:
 *   API key:  Proxy injects x-api-key on every request.
 *   OAuth:    Container CLI exchanges its placeholder token for a temp
 *             API key via /api/oauth/claude_cli/create_api_key.
 *             Proxy injects real OAuth token on that exchange request;
 *             subsequent requests carry the temp key which is valid as-is.
 */
import { createServer, Server } from 'http';
import { request as httpsRequest } from 'https';
import { request as httpRequest, RequestOptions } from 'http';

import fs from 'fs';
import path from 'path';

import { readEnvFile } from './env.js';
import { logger } from './logger.js';

// Health endpoint dependencies (lazy-loaded to avoid circular imports)
let _healthDeps: {
  getChannels: () => { name: string }[];
  getRegisteredGroups: () => Record<string, unknown>;
  assistantName: string;
} | null = null;

export function setHealthDeps(deps: typeof _healthDeps): void {
  _healthDeps = deps;
}

// --- Daily spend tracking ---
const DAILY_LIMIT_USD = (() => {
  const parsed = parseFloat(process.env.DAILY_API_LIMIT_USD || '20');
  return Number.isNaN(parsed) ? 20 : parsed;
})();
const COST_STATE_FILE = path.join(process.cwd(), 'store', 'daily-spend.json');

interface DailySpend {
  date: string;
  input_tokens: number;
  output_tokens: number;
  estimated_usd: number;
  limit_hit: boolean;
}

// In-memory cache — avoids disk reads on every API request
let spendCache: DailySpend | null = null;

function loadDailySpend(): DailySpend {
  const today = new Date().toISOString().slice(0, 10);

  // Return cache if same day
  if (spendCache && spendCache.date === today) return spendCache;

  // Try loading from disk
  try {
    const data = JSON.parse(fs.readFileSync(COST_STATE_FILE, 'utf-8'));
    if (data.date === today) {
      spendCache = data;
      return data;
    }
  } catch {
    /* first run or new day */
  }

  spendCache = {
    date: today,
    input_tokens: 0,
    output_tokens: 0,
    estimated_usd: 0,
    limit_hit: false,
  };
  return spendCache;
}

function saveDailySpend(spend: DailySpend): void {
  spendCache = spend;
  try {
    fs.mkdirSync(path.dirname(COST_STATE_FILE), { recursive: true });
    fs.writeFileSync(COST_STATE_FILE, JSON.stringify(spend, null, 2));
  } catch {
    /* best effort */
  }
}

// Approximate costs per 1M tokens (Sonnet 4.6 / Opus 4.6 blended estimate)
const INPUT_COST_PER_M = 3.0; // $3/MTok input (blended)
const OUTPUT_COST_PER_M = 15.0; // $15/MTok output (blended)

function trackUsage(responseBody: string): void {
  try {
    const data = JSON.parse(responseBody);
    const usage = data?.usage;
    if (!usage) return;

    const spend = loadDailySpend();
    const inputTokens = usage.input_tokens || 0;
    const outputTokens = usage.output_tokens || 0;

    spend.input_tokens += inputTokens;
    spend.output_tokens += outputTokens;
    spend.estimated_usd =
      (spend.input_tokens / 1_000_000) * INPUT_COST_PER_M +
      (spend.output_tokens / 1_000_000) * OUTPUT_COST_PER_M;

    if (spend.estimated_usd >= DAILY_LIMIT_USD && !spend.limit_hit) {
      spend.limit_hit = true;
      logger.error(
        { estimated_usd: spend.estimated_usd, limit: DAILY_LIMIT_USD },
        'DAILY API SPEND LIMIT HIT',
      );
    }

    saveDailySpend(spend);
  } catch {
    /* non-JSON response, ignore */
  }
}

function isDailyLimitHit(): boolean {
  const spend = loadDailySpend();
  return spend.limit_hit;
}

export type AuthMode = 'api-key' | 'oauth';

export interface ProxyConfig {
  authMode: AuthMode;
}

export function startCredentialProxy(
  port: number,
  host = '127.0.0.1',
): Promise<Server> {
  const secrets = readEnvFile([
    'ANTHROPIC_API_KEY',
    'CLAUDE_CODE_OAUTH_TOKEN',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_BASE_URL',
  ]);

  const authMode: AuthMode = secrets.ANTHROPIC_API_KEY ? 'api-key' : 'oauth';
  const oauthToken =
    secrets.CLAUDE_CODE_OAUTH_TOKEN || secrets.ANTHROPIC_AUTH_TOKEN;

  const upstreamUrl = new URL(
    secrets.ANTHROPIC_BASE_URL || 'https://api.anthropic.com',
  );
  const isHttps = upstreamUrl.protocol === 'https:';
  const makeRequest = isHttps ? httpsRequest : httpRequest;

  return new Promise((resolve, reject) => {
    const server = createServer((req, res) => {
      // Health check endpoint
      if (req.method === 'GET' && req.url === '/health') {
        const body = JSON.stringify({
          status: 'ok',
          agent: _healthDeps?.assistantName ?? 'unknown',
          uptime: Math.round(process.uptime()),
          channels: (_healthDeps?.getChannels() ?? []).map((c) => c.name),
          groups: Object.keys(_healthDeps?.getRegisteredGroups() ?? {}).length,
          port,
          model: process.env.CLAUDE_MODEL || 'unknown',
          timestamp: new Date().toISOString(),
        });
        res.writeHead(200, {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
        });
        res.end(body);
        return;
      }

      const chunks: Buffer[] = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        const body = Buffer.concat(chunks);

        // Block requests when daily spend limit is reached
        if (isDailyLimitHit() && req.url?.includes('/messages')) {
          const spend = loadDailySpend();
          logger.warn(
            { estimated_usd: spend.estimated_usd, limit: DAILY_LIMIT_USD },
            'Blocking API request — daily spend limit reached',
          );
          res.writeHead(429, { 'content-type': 'application/json' });
          res.end(
            JSON.stringify({
              type: 'error',
              error: {
                type: 'rate_limit_error',
                message: `Daily spend limit ($${DAILY_LIMIT_USD}) reached. Resets at midnight.`,
              },
            }),
          );
          return;
        }

        const headers: Record<string, string | number | string[] | undefined> =
          {
            ...(req.headers as Record<string, string>),
            host: upstreamUrl.host,
            'content-length': body.length,
          };

        // Strip hop-by-hop headers that must not be forwarded by proxies
        delete headers['connection'];
        delete headers['keep-alive'];
        delete headers['transfer-encoding'];

        if (authMode === 'api-key') {
          // API key mode: inject x-api-key on every request
          delete headers['x-api-key'];
          headers['x-api-key'] = secrets.ANTHROPIC_API_KEY;
        } else {
          // OAuth mode: replace placeholder Bearer token with the real one
          // only when the container actually sends an Authorization header
          // (exchange request + auth probes). Post-exchange requests use
          // x-api-key only, so they pass through without token injection.
          if (headers['authorization']) {
            delete headers['authorization'];
            if (oauthToken) {
              headers['authorization'] = `Bearer ${oauthToken}`;
            }
          }
        }

        const upstream = makeRequest(
          {
            hostname: upstreamUrl.hostname,
            port: upstreamUrl.port || (isHttps ? 443 : 80),
            path: req.url,
            method: req.method,
            headers,
          } as RequestOptions,
          (upRes) => {
            res.writeHead(upRes.statusCode!, upRes.headers);
            // Track token usage from API responses
            const respChunks: Buffer[] = [];
            upRes.on('data', (chunk) => {
              respChunks.push(chunk);
              res.write(chunk);
            });
            upRes.on('end', () => {
              res.end();
              if (req.url?.includes('/messages')) {
                trackUsage(Buffer.concat(respChunks).toString());
              }
            });
          },
        );

        upstream.on('error', (err) => {
          logger.error(
            { err, url: req.url },
            'Credential proxy upstream error',
          );
          if (!res.headersSent) {
            res.writeHead(502);
            res.end('Bad Gateway');
          }
        });

        upstream.write(body);
        upstream.end();
      });
    });

    server.listen(port, host, () => {
      logger.info({ port, host, authMode }, 'Credential proxy started');
      resolve(server);
    });

    server.on('error', reject);
  });
}

/** Detect which auth mode the host is configured for. */
export function detectAuthMode(): AuthMode {
  const secrets = readEnvFile(['ANTHROPIC_API_KEY']);
  return secrets.ANTHROPIC_API_KEY ? 'api-key' : 'oauth';
}
