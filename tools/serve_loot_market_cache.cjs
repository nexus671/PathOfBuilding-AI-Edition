'use strict';

const { createServer } = require('node:http');
const { setTimeout: delay } = require('node:timers/promises');

const upstreamBase = 'https://poe.ninja/poe1/api/economy/';
const exchange = new Set(['Currency', 'Fragment', 'Runegraft', 'AllflameEmber', 'Tattoo', 'Omen', 'DjinnCoin', 'Ducat',
  'EnshroudingCrystal', 'DivinationCard', 'Artifact', 'Oil', 'DeliriumOrb', 'Scarab', 'Astrolabe', 'Thread', 'Fossil',
  'Resonator', 'Essence']);
const stash = new Set(['Map', 'BlightedMap', 'BlightRavagedMap', 'UniqueWeapon', 'UniqueArmour', 'UniqueAccessory',
  'UniqueJewel', 'UniqueFlask', 'UniqueMap', 'SkillGem', 'ImbuedGem', 'BaseType']);
const stashLimit = 12 * 1024 * 1024;
const cacheLimit = 48 * 1024 * 1024;
const freshestAge = 3600;
const leaguePattern = /^[\w -]{1,80}$/;

class MarketError extends Error {
  constructor(status, message, retryAfter) {
    super(message);
    this.status = status;
    this.retryAfter = retryAfter;
  }
}

function overviewRoute(category) {
  if (exchange.has(category)) return 'exchange/current/overview';
  if (stash.has(category)) return 'stash/current/item/overview';
  return null;
}

function requestKey(raw) {
  if (!raw || raw.length > 512 || !raw.startsWith('/') || raw.startsWith('//')) {
    throw new MarketError(404, 'Unknown market route');
  }
  const url = new URL(raw, 'http://localhost');
  if (url.pathname === '/leagues' && !url.search) return { key: 'leagues', kind: 'leagues', limit: 65536 };
  const route = url.pathname.slice(1);
  const isStash = route === 'stash/current/item/overview';
  if (!isStash && route !== 'exchange/current/overview') throw new MarketError(404, 'Unknown market route');
  const league = url.searchParams.get('league');
  const category = url.searchParams.get('type');
  if (url.searchParams.size !== 2 || !leaguePattern.test(league || '') || overviewRoute(category) !== route) {
    throw new MarketError(400, 'Choose a supported item category and league');
  }
  const params = new URLSearchParams({ league, type: category });
  return { key: route + '?' + params, league, kind: isStash ? 'stash' : 'exchange', limit: isStash ? stashLimit : 2 * 1024 * 1024 };
}

function ageSource(headers, now, previous) {
  const value = headers.get('date');
  const date = value == null && previous ? previous.sourceAt : Date.parse(value);
  const ageHeader = headers.get('age');
  const age = ageHeader == null ? 0 : /^\d+$/.test(ageHeader) ? Number(ageHeader) : NaN;
  const responseAt = Math.min(now,date,now-age*1000);
  const sourceAt = Math.min(responseAt,previous?.sourceAt ?? now);
  if (!Number.isFinite(sourceAt) || date > now + 300000 || now - sourceAt > freshestAge * 1000 ||
      headers.get('cf-cache-status')?.toLowerCase() === 'stale') {
    throw new MarketError(502, 'Provider response is stale or has invalid freshness headers');
  }
  return { sourceAt,responseAt };
}

function responsePolicy(headers, previous) {
  const policy = headers.get('cache-control');
  if (policy==null && previous) return { store:previous.store, ttl:previous.ttl };
  const directives = (policy || '').split(',').map(part=>part.trim().toLowerCase());
  const store = !directives.some(part=>/^(?:no-store|private)(?:=|$)/.test(part));
  if (!store || directives.some(part=>/^no-cache(?:=|$)/.test(part))) return { store, ttl:0 };
  const seconds = name => Number(directives.find(part=>part.startsWith(name+'='))?.split('=')[1]);
  const shared = seconds('s-maxage');
  const ttl = Number.isFinite(shared) ? shared : seconds('max-age');
  return { store, ttl:Math.max(0,Math.min(300,Number.isFinite(ttl) ? ttl : 300)) };
}

function retrySeconds(headers, now) {
  const raw = headers.get('retry-after') || '';
  const requested = /^\d+$/.test(raw) ? Number(raw) : Math.ceil((Date.parse(raw) - now) / 1000);
  return Math.max(15, Math.min(Number.isFinite(requested) ? requested : 60, 7 * 86400));
}

async function boundedBody(response, limit) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body ?? []) {
    bytes += chunk.byteLength;
    if (bytes > limit) throw new MarketError(502, 'Provider response exceeds its size limit');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, bytes);
}

function validatePayload(value, kind) {
  if (kind === 'leagues') {
    const ids = new Set(value.map(entry => {
      if (typeof entry?.id !== 'string' || !leaguePattern.test(entry.id) || typeof entry.name !== 'string') {
        throw new MarketError(502, 'Provider returned an invalid league');
      }
      return entry.id;
    }));
    if (ids.size === 0 || ids.size > 100 || ids.size !== value.length) throw new MarketError(502, 'Provider league list is invalid');
    return ids;
  }
  if (!Array.isArray(value?.lines)) throw new MarketError(502, 'Provider overview is invalid');
  if (kind === 'exchange' && (!Array.isArray(value.items) || value.core?.primary !== 'chaos')) {
    throw new MarketError(502, 'Provider exchange overview is invalid');
  }
  return null;
}

function createMarketCache({ agent, fetcher = fetch, now = Date.now, spacingMs = 1000 } = {}) {
  if (!agent || agent.length > 250 || /[^ -~]/.test(agent)) throw new Error('Set a descriptive market User-Agent including an operator contact');
  const cache = new Map();
  const running = new Map();
  let size = 0;
  let retryAt = 0;
  let nextAt = 0;
  let queue = Promise.resolve();
  const stats = { hits: 0, requests: 0, coalesced: 0, rejected: 0 };

  function remove(key) {
    size -= cache.get(key)?.body.length || 0;
    cache.delete(key);
  }

  function save(key, entry) {
    remove(key);
    if (!entry.store) return;
    cache.set(key, entry);
    size += entry.body.length;
    while (cache.size > 48 || size > cacheLimit) {
      const oldest = cache.keys().next().value;
      remove(oldest);
    }
  }

  async function refresh(details, deadline) {
    const queuedAt = now();
    if (retryAt > queuedAt) throw new MarketError(429,'Provider cooldown',Math.ceil((retryAt-queuedAt)/1000));
    const sendAt = Math.max(queuedAt,nextAt);
    if (sendAt>=deadline) throw new MarketError(503,'Price refresh queue deadline expired',15);
    if (sendAt>queuedAt) await delay(sendAt-queuedAt);
    const budget = deadline-now();
    if (budget<=0) throw new MarketError(503,'Price refresh queue deadline expired',15);
    const cached = cache.get(details.key);
    if (cached && now()-cached.sourceAt>=freshestAge*1000) remove(details.key);
    const prior = cache.get(details.key);
    const headers = { Accept: 'application/json', 'User-Agent': agent };
    if (prior?.etag) headers['If-None-Match'] = prior.etag;
    nextAt = now() + spacingMs;
    stats.requests++;
    const response = await fetcher(upstreamBase + details.key, { headers, redirect: 'error', signal: AbortSignal.timeout(Math.min(15000,budget)) });
    try {
      const at = now();
      if (response.status === 429 || response.status === 503) {
        const seconds = retrySeconds(response.headers,at);
        retryAt = at + seconds * 1000;
        throw new MarketError(response.status,'Provider temporarily unavailable',seconds);
      }
      const policy = responsePolicy(response.headers,response.status===304 ? prior : undefined);
      if (response.status === 304 && prior?.etag) {
        let timing;
        try {
          timing = ageSource(response.headers,at,prior);
        } catch (error) {
          remove(details.key);
          throw error;
        }
        const entry = { ...prior, ...policy, sourceAt:timing.sourceAt,
          validUntil:Math.min(timing.responseAt+policy.ttl*1000,timing.sourceAt+freshestAge*1000) };
        save(details.key,entry);
        return entry;
      }
      if (response.status !== 200) throw new MarketError(response.status >= 400 && response.status < 600 ? response.status : 502,'Provider did not return prices');
      const body = await boundedBody(response,details.limit);
      const leagues = validatePayload(JSON.parse(body.toString('utf8')),details.kind);
      const timing = ageSource(response.headers,now());
      const rawTag = response.headers.get('etag');
      const etag = rawTag?.length <= 160 && /^(?:W\/)?"[^"\x00-\x1f]*"$/.test(rawTag) ? rawTag : null;
      const entry = { body, leagues, sourceAt:timing.sourceAt, etag, ...policy,
        validUntil:Math.min(timing.responseAt+policy.ttl*1000,timing.sourceAt+freshestAge*1000) };
      save(details.key,entry);
      return entry;
    } finally {
      if (response.body && !response.body.locked) await response.body.cancel().catch(() => {});
    }
  }

  function get(details) {
    const entry = cache.get(details.key);
    if (entry?.validUntil > now()) {
      stats.hits++;
      return Promise.resolve(entry);
    }
    if (running.has(details.key)) {
      stats.coalesced++;
      return running.get(details.key);
    }
    if (running.size >= 12) throw new MarketError(503,'Price refresh queue is full',15);
    const deadline = now()+18000;
    const pending = queue.then(() => refresh(details,deadline));
    queue = pending.catch(() => {});
    running.set(details.key,pending);
    return pending.finally(() => running.delete(details.key));
  }

  return createServer({ requestTimeout: 20000, headersTimeout: 10000 }, async (request,res) => {
    try {
      if (request.method !== 'GET') throw new MarketError(405,'Use GET for market requests');
      if (request.url === '/health') {
        res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});
        res.end(JSON.stringify({ status:'ready', cached:cache.size, pending:running.size, ...stats }));
        return;
      }
      const details = requestKey(request.url);
      if (details.league && !(await get(requestKey('/leagues'))).leagues.has(details.league)) {
        throw new MarketError(404,'Trade league is not active');
      }
      const entry = await get(details);
      const age = Math.max(0,Math.ceil((now()-entry.sourceAt)/1000));
      if (age > freshestAge) throw new MarketError(502,'Provider response is stale');
      const headers = { 'Content-Type':'application/json', Date:new Date(entry.sourceAt).toUTCString(),
        Age:String(age), 'Cache-Control':entry.ttl ? 'private, max-age=0' : 'no-store' };
      if (entry.etag) headers.ETag = entry.etag;
      if (entry.etag && request.headers['if-none-match'] === entry.etag) {
        res.writeHead(304,headers);
        res.end();
        return;
      }
      res.writeHead(200,headers);
      res.end(entry.body);
    } catch (error) {
      stats.rejected++;
      const headers = { 'Content-Type':'application/json','Cache-Control':'no-store' };
      if (error.retryAfter) headers['Retry-After'] = String(error.retryAfter);
      res.writeHead(error.status || 502,headers);
      res.end(JSON.stringify({ error: error instanceof MarketError ? error.message : 'Provider response unavailable' }));
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.POB_MARKET_CACHE_PORT || 9410);
  if (!Number.isInteger(port) || port<1 || port>65535) throw new Error('Choose a valid cache port');
  createMarketCache({ agent:process.env.POB_MARKET_UPSTREAM_AGENT }).listen(port,'127.0.0.1',() => {
    process.stdout.write(`PoB market cache listening on 127.0.0.1:${port}\n`);
  });
}

module.exports = { createMarketCache, requestKey, overviewRoute, ageSource, boundedBody, validatePayload };
