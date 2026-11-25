'use strict';

const { isDeepStrictEqual } = require('node:util');
const { requestKey, overviewRoute, ageSource, boundedBody, validatePayload, providerFailureReasons } = require('./serve_loot_market_cache.cjs');

const coreFeeds = ['Currency', 'Oil', 'Omen', 'Essence', 'Thread', 'Fragment', 'Resonator', 'Artifact'];
const positive = value => Number.isFinite(value) && value>0;
const exchangeText = value => typeof value==='string' && Buffer.byteLength(value,'utf8')<=200
  && /[^ ]/.test(value) && !/[\x00-\x1f\x7f]/.test(value);
const stashIdentityFields = ['name','baseType','gemLevel','gemQuality','corrupted','variant','links','mapTier','chaosValue',
  'itemType','itemClass','levelRequired','stackSize','mapRegion','implicitModifiers','explicitModifiers','mutatedModifiers','metadata'];

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

function gemTuple(row) {
  const variant = row.variant;
  const canonical = variant != null && variant !== '';
  const quality = canonical ? row.gemQuality ?? 0 : row.gemQuality;
  const corrupted = canonical ? row.corrupted ?? false : row.corrupted;
  if (!exchangeText(row.name) || /["\\]/.test(row.name) || !Number.isInteger(row.gemLevel)
      || row.gemLevel < 1 || row.gemLevel > 40 || !Number.isInteger(quality)
      || quality < 0 || quality > 100 || typeof corrupted !== 'boolean') return null;
  return [row.name,row.gemLevel,quality,corrupted];
}

function regularGemVariant(row, tuple) {
  if (row.baseType != null && row.baseType !== '' && row.baseType !== row.name
      || ['Imbued','imbued','TransfiguredGem','transfiguredGem','transfigured'].some(flag=>row[flag]!=null && row[flag]!==false)
      || row.metadata?.gemKind === 'transfigured' || row.metadata?.gemKind === 'imbued') return false;
  if (row.variant == null || row.variant === '') return true;
  const [,level,quality,corrupted] = tuple;
  const expected = String(level) + (quality > 0 ? '/' + quality : '') + (corrupted ? 'c' : '');
  return row.variant === expected;
}

function exactGemQuotes(rows) {
  const identities = new Map();
  const variants = new Map();
  for (const row of rows) {
    const id=row?.detailsId;
    const validId=typeof id==='string' && /^[A-Za-z0-9_.-]{1,200}$/.test(id);
    const tuple=gemTuple(row);
    if (!tuple) {
      if (validId) identities.set(id,false);
      continue;
    }
    const key=JSON.stringify(tuple);
    const eligible=validId && positive(row.chaosValue) && positive(row.count) && positive(row.listingCount)
      && regularGemVariant(row,tuple);
    if (validId) {
      const signature=eligible && JSON.stringify([key,row.chaosValue]);
      const prior=identities.get(id);
      identities.set(id,prior===undefined || prior===signature ? signature : false);
    }
    const volume=eligible ? Math.min(row.count,row.listingCount) : 0;
    const variant=variants.get(key);
    variants.set(key,{ id,volume:!variant ? volume : variant.id===id ? Math.min(variant.volume,volume) : 0 });
  }
  return [...variants.values()].filter(row=>row.volume>=20 && identities.get(row.id)).length;
}

const mapNames = {Map:'Map',BlightedMap:'Blighted Map',BlightRavagedMap:'Blight-ravaged Map'};
function exactMapTiers(rows, category) {
  const quotes=new Map(), identities=new Map();
  for (const row of rows) {
    let tier;
    for (let value=1;value<=16;value++) {
      if (row.name===`${mapNames[category]} (Tier ${value})`
          && (row.mapTier==null || row.mapTier===0 || row.mapTier===value)
          && (row.baseType==null || row.baseType==='')) tier=value;
    }
    const id=typeof row.detailsId==='string' && /^[A-Za-z0-9_.-]{1,200}$/.test(row.detailsId) ? row.detailsId : null;
    let priced=tier && id && positive(row.chaosValue) && positive(row.count) && positive(row.listingCount);
    if (id) {
      let owner=priced ? tier : false;
      const previous=identities.get(id);
      if (previous!==undefined && previous!==owner) {
        if (previous) quotes.set(previous,false);
        owner=false;
      }
      identities.set(id,owner);
      priced=owner;
    }
    if (tier) {
      const previous=quotes.get(tier);
      if (!priced || previous===false || previous && (previous.id!==id || previous.price!==row.chaosValue
          || !isDeepStrictEqual(previous.variant,row.variant ?? null))) quotes.set(tier,false);
      else {
        const volume=Math.min(row.count,row.listingCount);
        if (!previous || volume<previous.volume) quotes.set(tier,{id,price:row.chaosValue,variant:row.variant ?? null,volume});
      }
    }
  }
  return [...quotes].filter(([,quote])=>quote && quote.volume>=20).map(([tier])=>tier).sort((a,b)=>a-b);
}

function advisoryGemQuotes(rows, candidates) {
  const variants=new Map();
  const optionalInteger=(value,minimum,maximum)=>value==null
    || Number.isInteger(value) && value>=minimum && value<=maximum;
  for (const row of rows) {
    if (!exchangeText(row.name) || !exchangeText(row.variant) || /["\\]/.test(row.name+row.variant)) continue;
    const support=row.variant.toLowerCase().replace(/ support$/,'');
    if (!support) continue;
    if (!optionalInteger(row.gemLevel,1,40) || !optionalInteger(row.gemQuality,0,100)
        || row.corrupted!=null && typeof row.corrupted!=='boolean') continue;
    const combination=JSON.stringify([row.name,support]);
    const key=JSON.stringify([combination,row.gemLevel ?? null,row.gemQuality ?? null,row.corrupted ?? null]);
    const id=row.detailsId;
    const prior=variants.get(key);
    // Even an invalidated ID can have claimed this variant.
    variants.set(key,prior===undefined || prior && prior.id===id ? {id,combination} : false);
  }
  return new Set([...variants.values()].filter(row=>row && candidates.get(row.id)?.liquid)
    .map(row=>row.combination)).size;
}

function priceEvidence(payload, category, kind) {
  if (kind==='exchange') {
    const names = new Map();
    for (const item of payload.items) {
      if (!exchangeText(item?.id) || !exchangeText(item?.name) ||
          names.has(item.id) && names.get(item.id)!==item.name) {
        throw new Error('Invalid or conflicting exchange item ID');
      }
      names.set(item.id,item.name);
    }
    const candidates = new Map();
    for (const line of payload.lines) {
      if (!exchangeText(line?.id)) throw new Error('Invalid exchange price line ID');
      const name=names.get(line.id);
      if (!name) continue;
      const prior=candidates.get(name);
      if (!positive(line.primaryValue) || !positive(line.volumePrimaryValue) || prior===false ||
          prior && (prior.id!==line.id || prior.primaryValue!==line.primaryValue)) {
        candidates.set(name,false);
      } else if (!prior || line.volumePrimaryValue<prior.volumePrimaryValue) {
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
  const candidates = new Map();
  for (const row of payload.lines) {
    const id = row?.detailsId;
    if (typeof id!=='string' || !/^[A-Za-z0-9_.-]{1,200}$/.test(id)) continue;
    const previous = candidates.get(id);
    const valid = typeof row.name==='string' && row.name.length<=200 && row.name.trim() &&
      !/[\x00-\x1f\x7f]/.test(row.name) && positive(row.chaosValue);
    if (!valid || previous===false || previous && stashIdentityFields.some(field=>!isDeepStrictEqual(previous.row[field],row[field]))) {
      candidates.set(id,false);
    } else {
      const liquid = Number.isFinite(row.count) && row.count>=20 && Number.isFinite(row.listingCount) && row.listingCount>=20;
      candidates.set(id,{row:previous?.row ?? row,liquid:liquid && (previous?.liquid ?? true)});
    }
  }
  const priced = [...candidates.values()].filter(Boolean);
  if (!priced.length && !mapNames[category]) throw new Error('No unambiguous priced stash variants with stable IDs');
  const listed = priced.filter(row=>row.liquid);
  if (mapNames[category]) {
    const tiers=exactMapTiers(payload.lines,category);
    if (!tiers.length) throw new Error('No unambiguous liquid exact tier-wide map quote');
    return {priced:priced.length,listed:listed.length,exactMapTiers:tiers};
  }
  if (category==='ImbuedGem') {
    const advisory=advisoryGemQuotes(payload.lines,candidates);
    if (!advisory) throw new Error('No unambiguous listing-backed named gem and support variant');
    return {priced:priced.length,listed:listed.length,advisoryGemQuotes:advisory};
  }
  if (category==='SkillGem') {
    const exact=exactGemQuotes(payload.lines);
    if (!exact) throw new Error('No unambiguous listing-backed gem quote with a consistent level, quality and corruption');
    return { priced:priced.length, listed:listed.length, exactGemQuotes:exact };
  }
  return { priced:priced.length, listed:listed.length };
}

const nonnegativeInteger = value => Number.isSafeInteger(value) && value>=0;
const providerStates = new Set(['idle','ready','degraded','cooldown']);

function numericEvidence(target, source, fields) {
  for (const field of fields) {
    if (nonnegativeInteger(source?.[field])) target[field] = source[field];
  }
}

function healthEvidence(payload) {
  if (payload?.status!=='ready' || !nonnegativeInteger(payload.cached) || !nonnegativeInteger(payload.pending)) {
    throw new Error('Cache health response is incomplete');
  }
  const info = { cached:payload.cached, pending:payload.pending };
  numericEvidence(info,payload,['cachedBytes','serviceable','hits','requests','coalesced','rejected']);
  if (payload.snapshots!==undefined) {
    const snapshots = {};
    numericEvidence(snapshots,payload.snapshots,['restored','discarded','errors']);
    if (Object.keys(snapshots).length!==3 || snapshots.errors>0) throw new Error('Market snapshot storage is unavailable');
    info.snapshots = snapshots;
  }
  if (payload.rejections) {
    const rejections = {};
    numericEvidence(rejections,payload.rejections,['client','queue','cooldown']);
    if (Object.keys(rejections).length) info.rejections = rejections;
  }
  const provider = payload.provider;
  if (provider?.cooldownPersistence==='error') throw new Error('Provider cooldown state is unavailable');
  if (providerStates.has(provider?.state)) {
    const snapshot = {state:provider.state};
    if (provider.cooldownPersistence==='ready') snapshot.cooldownPersistence='ready';
    numericEvidence(snapshot,provider,['lastValidatedAt','cooldownSeconds','successes','failures']);
    if (provider.lastValidatedAt===null) snapshot.lastValidatedAt = null;
    const failure = provider.lastFailure;
    if (failure===null) snapshot.lastFailure = null;
    if (providerFailureReasons.includes(failure?.reason) && nonnegativeInteger(failure.at)) {
      snapshot.lastFailure = {at:failure.at,reason:failure.reason};
      if (Number.isInteger(failure.httpStatus) && failure.httpStatus>=100 && failure.httpStatus<=599) {
        snapshot.lastFailure.httpStatus = failure.httpStatus;
      }
    }
    info.provider = snapshot;
  }
  return info;
}

async function qualifyCache(raw, { league, extra = [], fetcher = fetch, now = Date.now } = {}) {
  const root = cacheRoot(raw);
  if (extra.some(category=>!overviewRoute(category))) throw new Error('Choose only supported optional market categories');
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

  const health=await probe('Cache health','health',healthEvidence);
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

  for (const category of new Set([...coreFeeds,...extra])) {
    const params=new URLSearchParams({league:selected,type:category});
    const path=overviewRoute(category)+'?'+params;
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
