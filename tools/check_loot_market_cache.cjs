'use strict';

const { requestKey, ageSource, boundedBody, validatePayload } = require('./serve_loot_market_cache.cjs');

const coreFeeds = ['Currency', 'Oil', 'Omen', 'Essence', 'Thread', 'Fragment', 'Resonator', 'Artifact'];
const optionalFeeds = new Map([
  ['DivinationCard', 'exchange/current/overview'],
  ...['Map','BlightedMap','BlightRavagedMap','UniqueWeapon','UniqueArmour','UniqueAccessory','UniqueJewel','UniqueFlask',
    'UniqueMap','SkillGem','ImbuedGem','BaseType'].map(category=>[category,'stash/current/item/overview']),
]);
const positive = value => Number.isFinite(value) && value>0;

function cacheRoot(raw) {
  let url;
  try { url = new URL(raw); } catch {}
  if (!url || url.protocol!=='https:' || url.username || url.password || url.search || url.hash ||
      !/^\/[\w/-]*$/.test(url.pathname)) {
    throw new Error('Use the cache HTTPS prefix without credentials, query parameters or a fragment');
  }
  url.pathname = url.pathname.replace(/\/+$/,'') + '/';
  return url.href;
}

function priceEvidence(payload, category, kind) {
  if (kind==='exchange') {
    const names = new Map();
    for (const item of payload.items) {
      if (typeof item?.id!=='string' || typeof item.name!=='string' ||
          names.has(item.id) && names.get(item.id)!==item.name) {
        throw new Error('Invalid or conflicting exchange item ID');
      }
      names.set(item.id,item.name);
    }
    const candidates = new Map();
    for (const line of payload.lines) {
      const name=names.get(line?.id);
      if (!name || !positive(line.primaryValue) || !positive(line.volumePrimaryValue)) continue;
      const prior=candidates.get(name);
      if (prior===false || prior && (prior.id!==line.id || prior.primaryValue!==line.primaryValue)) {
        candidates.set(name,false);
      } else if (!prior || line.volumePrimaryValue>prior.volumePrimaryValue) {
        candidates.set(name,line);
      }
    }
    const priced = [...candidates.values()].filter(Boolean);
    if (!priced.length) throw new Error('No matched, unambiguous exchange quotes');
    if (category==='Currency' && !(candidates.get('Orb of Alteration')?.volumePrimaryValue>=100)) {
      throw new Error('Missing liquid Orb of Alteration reference quote');
    }
    return { priced:priced.length };
  }
  const priced = payload.lines.filter(row=>typeof row?.name==='string' && typeof row.detailsId==='string'
    && row.detailsId.length>0 && positive(row.chaosValue));
  if (!priced.length) throw new Error('No priced stash variants with stable IDs');
  const listed = priced.filter(row=>row.count>=20 && row.listingCount>=20
    && Number.isFinite(row.count) && Number.isFinite(row.listingCount));
  if (category==='SkillGem' || category==='ImbuedGem') {
    const exact = listed.filter(row=>Number.isInteger(row.gemLevel) && row.gemLevel>0 &&
      Number.isInteger(row.gemQuality) && row.gemQuality>=0 && typeof row.corrupted==='boolean');
    if (!exact.length) throw new Error('Missing explicit level, quality and corruption on listing-backed gem quotes');
    return { priced:priced.length, listed:listed.length, exactGemQuotes:exact.length };
  }
  return { priced:priced.length, listed:listed.length };
}

async function qualifyCache(raw, { league, extra = [], fetcher = fetch, now = Date.now } = {}) {
  const root = cacheRoot(raw);
  if (extra.some(category=>!optionalFeeds.has(category))) throw new Error('Choose only supported optional market categories');
  const report = { status:'failed', league:null, probes:[] };

  async function probe(name, path, consume, limit=65536) {
    let response;
    try {
      response=await fetcher(root+path,{ redirect:'error', headers:{Accept:'application/json'},signal:AbortSignal.timeout(20000) });
      if (response.status!==200) {
        const retryAfter=response.headers.get('retry-after');
        const result={name,status:'failed',httpStatus:response.status};
        if (retryAfter && retryAfter.length<=100 && /^[\w ,:-]+$/.test(retryAfter)) result.retryAfter=retryAfter;
        report.probes.push(result);
        return null;
      }
      const payload=JSON.parse((await boundedBody(response,limit)).toString('utf8'));
      const details=consume(payload,response);
      report.probes.push({name,status:'passed',...details});
      return payload;
    } catch (error) {
      // Transport errors can embed proxy addresses or an operator's hostname.
      report.probes.push({name,status:'failed',reason:response ? (error instanceof SyntaxError ? 'Invalid JSON' : error.message) : 'HTTPS request failed'});
      return null;
    } finally {
      if (response?.body && !response.body.locked) await response.body.cancel().catch(()=>{});
    }
  }

  const health=await probe('Cache health','health',payload=>{
    if (payload?.status!=='ready' || !Number.isInteger(payload.cached) || !Number.isInteger(payload.pending)) {
      throw new Error('Cache health response is incomplete');
    }
    return { cached:payload.cached, pending:payload.pending };
  });
  if (!health) return report;
  const leagues=await probe('Trade leagues','leagues',(payload,response)=>{
    validatePayload(payload,'leagues');
    const at=now();
    const {sourceAt}=ageSource(response.headers,at);
    return { freshnessSeconds:Math.ceil((at-sourceAt)/1000) };
  });
  if (!leagues) return report;
  const selected=league ?? leagues[0].id;
  if (!leagues.some(row=>row.id===selected)) {
    report.probes.push({name:'Requested league',status:'failed',reason:'League is absent from the verified trade list'});
    return report;
  }
  report.league=selected;

  for (const category of [...coreFeeds,...new Set(extra)]) {
    const params=new URLSearchParams({league:selected,type:category});
    const path=(optionalFeeds.get(category) ?? 'exchange/current/overview')+'?'+params;
    const details=requestKey('/'+path);
    const passed=await probe(category,details.key,(payload,response)=>{
      validatePayload(payload,details.kind);
      const at=now();
      const {sourceAt}=ageSource(response.headers,at);
      return {freshnessSeconds:Math.ceil((at-sourceAt)/1000), ...priceEvidence(payload,category,details.kind)};
    },details.limit);
    const latest=report.probes.at(-1);
    if (!passed && (latest.httpStatus===429 || latest.httpStatus===503 || !latest.httpStatus && latest.reason==='HTTPS request failed')) {
      return report;
    }
  }
  if (report.probes.every(entry=>entry.status==='passed')) report.status='passed';
  return report;
}

if (require.main===module) {
  const [url,league,extra,...unexpected]=process.argv.slice(2);
  if (!url || unexpected.length) {
    console.error('Usage: node tools/check_loot_market_cache.cjs <cache HTTPS prefix> [league] [comma-separated optional categories]');
    process.exitCode=2;
  } else {
    qualifyCache(url,{league,extra:extra ? extra.split(',').filter(Boolean) : []}).then(report=>{
      console.log(JSON.stringify(report,null,2));
      if (report.status!=='passed') process.exitCode=1;
    }).catch(error=>{
      console.error(error.message);
      process.exitCode=2;
    });
  }
}

module.exports = { qualifyCache };
