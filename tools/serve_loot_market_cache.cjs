'use strict';

const { createServer } = require('node:http');
const { randomUUID } = require('node:crypto');
const { closeSync, fstatSync, lstatSync, openSync, readSync, renameSync, rmSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { openMarketSnapshots } = require('./loot_market_snapshots.cjs');

const upstreamBase = 'https://poe.ninja/poe1/api/economy/';
const exchange = new Set(['Currency', 'Fragment', 'Runegraft', 'AllflameEmber', 'Tattoo', 'Omen', 'DjinnCoin', 'Ducat',
  'EnshroudingCrystal', 'DivinationCard', 'Artifact', 'Oil', 'DeliriumOrb', 'Scarab', 'Astrolabe', 'Thread', 'Fossil',
  'Resonator', 'Essence']);
const stash = new Set(['Wombgift', 'Corpse', 'Viscera', 'Incubator', 'UniqueWeapon', 'UniqueArmour', 'UniqueAccessory',
  'UniqueFlask', 'UniqueJewel', 'ForbiddenJewel', 'ShrineBelt', 'UniqueTincture', 'UniqueRelic', 'SkillGem', 'ImbuedGem',
  'ClusterJewel', 'Map', 'BlightedMap', 'BlightRavagedMap', 'UniqueMap', 'ValdoMap', 'Invitation', 'Memory',
  'IncursionTemple', 'ScryingOrb', 'BaseType', 'Flask', 'Beast', 'Vial']);
const stashLimit = 12 * 1024 * 1024;
const cacheLimit = 48 * 1024 * 1024;
const freshestAge = 3600;
const maxRetrySeconds = 7 * 86400;
const leaguePattern = /^[\w -]{1,80}$/;
const providerFailureReasons = Object.freeze(['rate_limited','unavailable','access_denied','http_error','stale',
  'invalid_response','oversized','transport','timeout']);
const relayedFailureReasons = new Set(['invalid_response','oversized','stale']);

class MarketError extends Error {
  constructor(status, message, retryAfter, reason) {
    super(message);
    this.status = status;
    this.retryAfter = retryAfter;
    this.reason = reason;
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
    throw new MarketError(502, 'Provider response is stale or has invalid freshness headers',undefined,'stale');
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
  return Math.max(15, Math.min(Number.isFinite(requested) ? requested : 60, maxRetrySeconds));
}

function validTag(value) {
  return typeof value==='string' && value.length<=160 && /^(?:W\/)?"[^"\x00-\x1f]*"$/.test(value);
}

function openCooldownState(file, now) {
  const path = resolve(file);
  function save(until) {
    const temporary = path + '.' + randomUUID() + '.tmp';
    try {
      writeFileSync(temporary, String(until)+'\n', { flag:'wx',mode:0o600,flush:true });
      renameSync(temporary,path);
    } finally {
      rmSync(temporary,{force:true});
    }
  }
  try {
    let fd;
    try {
      if (!lstatSync(path).isFile()) throw new Error('Invalid cooldown record');
      fd = openSync(path,'r');
    }
    catch (error) { if (error.code!=='ENOENT') throw error; }
    let until = 0;
    if (fd!==undefined) {
      try {
        const value = Buffer.alloc(24);
        const info = fstatSync(fd);
        if (!info.isFile() || info.size>value.length) throw new Error('Invalid cooldown record');
        const count = readSync(fd,value,0,value.length,0);
        const text = value.subarray(0,count).toString('utf8');
        until = Number(text);
        if (!Number.isSafeInteger(until) || until<0 || text!==String(until)+'\n'
            || until>now+maxRetrySeconds*1000) throw new Error('Invalid cooldown deadline');
      } finally {
        closeSync(fd);
      }
    }
    save(until);
    return { until,save };
  } catch {
    throw new Error('Cannot open the market cooldown state. Check its format and state directory.');
  }
}

async function boundedBody(response, limit) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body ?? []) {
    bytes += chunk.byteLength;
    if (bytes > limit) throw new MarketError(502, 'Provider response exceeds its size limit',undefined,'oversized');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, bytes);
}

function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function recordList(value) {
  return Array.isArray(value) && value.every(record);
}

function validatePayload(value, kind) {
  if (kind === 'leagues') {
    if (!recordList(value)) throw new MarketError(502, 'Provider league list is invalid',undefined,'invalid_response');
    const ids = new Set(value.map(entry => {
      if (typeof entry?.id !== 'string' || !leaguePattern.test(entry.id) || typeof entry.name !== 'string') {
        throw new MarketError(502, 'Provider returned an invalid league',undefined,'invalid_response');
      }
      return entry.id;
    }));
    if (ids.size === 0 || ids.size > 100 || ids.size !== value.length) throw new MarketError(502, 'Provider league list is invalid',undefined,'invalid_response');
    return ids;
  }
  if (!record(value) || !recordList(value.lines)) throw new MarketError(502, 'Provider overview is invalid',undefined,'invalid_response');
  if (kind === 'exchange' && (!recordList(value.items) || !record(value.core) || value.core.primary !== 'chaos')) {
    throw new MarketError(502, 'Provider exchange overview is invalid',undefined,'invalid_response');
  }
  return null;
}

function createMarketCache({ agent, fetcher = fetch, now = Date.now, spacingMs = 1000, cooldownFile, snapshotDirectory } = {}) {
  if (!agent || agent.length > 250 || /[^ -~]/.test(agent)) throw new Error('Set a descriptive market User-Agent including an operator contact');
  const cache = new Map();
  const running = new Map();
  let size = 0;
  const cooldown = cooldownFile ? openCooldownState(cooldownFile,now()) : null;
  const snapshots = snapshotDirectory && openMarketSnapshots(snapshotDirectory,{
    now,requestKey,validatePayload,validTag,freshnessMs:freshestAge*1000,maxBodyBytes:stashLimit,
  });
  let retryAt = cooldown?.until ?? 0;
  let cooldownPersistence = cooldown ? 'ready' : null;
  let nextAt = 0;
  let queue = Promise.resolve();
  const stats = { hits: 0, requests: 0, coalesced: 0, rejected: 0 };
  const provider = { state:'idle',lastValidatedAt:null,lastFailure:null,successes:0,failures:0 };
  const rejections = { client:0,queue:0,cooldown:0 };

  function persistCooldown() {
    try {
      cooldown.save(retryAt);
      cooldownPersistence = 'ready';
    } catch {
      cooldownPersistence = 'error';
    }
  }

  function health() {
    const at = now();
    let serviceable = 0;
    for (const entry of cache.values()) if (entry.validUntil>at) serviceable++;
    const cooldownSeconds = Math.max(0,Math.ceil((retryAt-at)/1000));
    return {status:'ready',cached:cache.size,pending:running.size,...stats,cachedBytes:size,serviceable,
      ...(snapshots ? {snapshots:snapshots.health()} : {}),
      provider:{...provider,state:cooldownSeconds>0 ? 'cooldown' : provider.state,cooldownSeconds,
        ...(cooldownPersistence ? { cooldownPersistence } : {})},rejections:{...rejections}};
  }

  function validated() {
    provider.successes++;
    provider.state = 'ready';
    provider.lastValidatedAt = now();
  }

  function remove(key, removeSnapshot = true) {
    size -= cache.get(key)?.body.length || 0;
    cache.delete(key);
    if (removeSnapshot) snapshots?.remove(key);
  }

  function save(key, entry, writeSnapshot = true) {
    remove(key,false);
    if (!entry.store) {
      snapshots?.remove(key);
      return;
    }
    cache.set(key, entry);
    size += entry.body.length;
    while (cache.size > 48 || size > cacheLimit) {
      const oldest = cache.keys().next().value;
      remove(oldest);
    }
    if (writeSnapshot && cache.has(key)) snapshots?.save(key,entry);
  }

  if (snapshots) {
    for (const {key,entry} of snapshots.entries()) save(key,entry,false);
  }

  async function refresh(details, deadline) {
    const queuedAt = now();
    if (retryAt > queuedAt) {
      rejections.cooldown++;
      throw new MarketError(429,'Provider cooldown',Math.ceil((retryAt-queuedAt)/1000));
    }
    if (cooldownPersistence==='error') {
      persistCooldown();
      if (cooldownPersistence==='error') {
        rejections.cooldown++;
        throw new MarketError(503,'Provider cooldown state is unavailable',60);
      }
    }
    const sendAt = Math.max(queuedAt,nextAt);
    if (sendAt>=deadline) {
      rejections.queue++;
      throw new MarketError(503,'Price refresh queue deadline expired',15);
    }
    if (sendAt>queuedAt) await delay(sendAt-queuedAt);
    const budget = deadline-now();
    if (budget<=0) {
      rejections.queue++;
      throw new MarketError(503,'Price refresh queue deadline expired',15);
    }
    const cached = cache.get(details.key);
    if (cached && now()-cached.sourceAt>=freshestAge*1000) remove(details.key);
    const prior = cache.get(details.key);
    const headers = { Accept: 'application/json', 'User-Agent': agent };
    if (prior?.etag) headers['If-None-Match'] = prior.etag;
    nextAt = now() + spacingMs;
    stats.requests++;
    let response;
    let failureReason = 'transport';
    try {
      response = await fetcher(upstreamBase + details.key, { headers, redirect: 'error', signal: AbortSignal.timeout(Math.min(15000,budget)) });
      failureReason = 'invalid_response';
      const at = now();
      if (response.status === 429 || response.status === 503) {
        const seconds = retrySeconds(response.headers,at);
        retryAt = at + seconds * 1000;
        if (cooldown) persistCooldown();
        throw new MarketError(response.status,'Provider temporarily unavailable',seconds,response.status===429 ? 'rate_limited' : 'unavailable');
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
        validated();
        return entry;
      }
      if (response.status !== 200) {
        const reason = response.status===401 || response.status===403 ? 'access_denied'
          : response.status>=500 ? 'unavailable' : response.status===304 ? 'invalid_response' : 'http_error';
        throw new MarketError(response.status >= 400 && response.status < 600 ? response.status : 502,'Provider did not return prices',undefined,reason);
      }
      failureReason = 'transport';
      const body = await boundedBody(response,details.limit);
      failureReason = 'invalid_response';
      const leagues = validatePayload(JSON.parse(body.toString('utf8')),details.kind);
      const timing = ageSource(response.headers,now());
      const rawTag = response.headers.get('etag');
      const etag = validTag(rawTag) ? rawTag : null;
      const entry = { body, leagues, sourceAt:timing.sourceAt, etag, ...policy,
        validUntil:Math.min(timing.responseAt+policy.ttl*1000,timing.sourceAt+freshestAge*1000) };
      save(details.key,entry);
      validated();
      return entry;
    } catch (error) {
      const reason = error instanceof MarketError && providerFailureReasons.includes(error.reason) ? error.reason
        : error?.name==='TimeoutError' || error?.name==='AbortError' ? 'timeout' : failureReason;
      const httpStatus = response && Number.isInteger(response.status) && response.status>=100 && response.status<=599 ? response.status : undefined;
      provider.failures++;
      provider.state = 'degraded';
      provider.lastFailure = {at:now(),reason,...(httpStatus===undefined ? {} : {httpStatus})};
      if (!(error instanceof MarketError) && reason === 'invalid_response') {
        throw new MarketError(502,'Provider response unavailable',undefined,reason);
      }
      throw error;
    } finally {
      if (response?.body && !response.body.locked) await response.body.cancel().catch(() => {});
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
    if (running.size >= 12) {
      rejections.queue++;
      throw new MarketError(503,'Price refresh queue is full',15);
    }
    const deadline = now()+18000;
    const pending = queue.then(() => refresh(details,deadline));
    queue = pending.catch(() => {});
    running.set(details.key,pending);
    return pending.finally(() => running.delete(details.key));
  }

  return createServer({ requestTimeout: 20000, headersTimeout: 10000 }, async (request,res) => {
    try {
      if (request.method !== 'GET') {
        rejections.client++;
        throw new MarketError(405,'Use GET for market requests');
      }
      if (request.url === '/health') {
        res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});
        res.end(JSON.stringify(health()));
        return;
      }
      let details;
      try { details = requestKey(request.url); }
      catch (error) { rejections.client++;throw error; }
      if (details.league && !(await get(requestKey('/leagues'))).leagues.has(details.league)) {
        rejections.client++;
        throw new MarketError(404,'Trade league is not active');
      }
      const entry = await get(details);
      const age = Math.max(0,Math.ceil((now()-entry.sourceAt)/1000));
      if (age > freshestAge) throw new MarketError(502,'Provider response is stale',undefined,'stale');
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
      if (error?.retryAfter) headers['Retry-After'] = String(error.retryAfter);
      if (error instanceof MarketError && error.status === 502 && relayedFailureReasons.has(error.reason)) {
        headers['X-PoB-Market-Failure'] = error.reason;
      }
      res.writeHead(error?.status || 502,headers);
      res.end(JSON.stringify({ error: error instanceof MarketError ? error.message : 'Provider response unavailable' }));
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.POB_MARKET_CACHE_PORT || 9410);
  if (!Number.isInteger(port) || port<1 || port>65535) throw new Error('Choose a valid cache port');
  createMarketCache({ agent:process.env.POB_MARKET_UPSTREAM_AGENT,
    cooldownFile:process.env.POB_MARKET_COOLDOWN_FILE,
    snapshotDirectory:process.env.POB_MARKET_SNAPSHOT_DIRECTORY }).listen(port,'127.0.0.1',() => {
    process.stdout.write(`PoB market cache listening on 127.0.0.1:${port}\n`);
  });
}

module.exports = { createMarketCache, requestKey, overviewRoute, ageSource, boundedBody, validatePayload, providerFailureReasons };
