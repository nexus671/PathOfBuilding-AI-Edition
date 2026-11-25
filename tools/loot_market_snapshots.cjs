'use strict';

const { createHash, randomUUID } = require('node:crypto');
const { closeSync, fstatSync, lstatSync, openSync, readSync, readdirSync, renameSync, rmSync, writeFileSync } = require('node:fs');
const { join, resolve } = require('node:path');

const filenamePattern = /^pob-market-[a-f0-9]{64}\.snapshot$/;
const temporaryPattern = /^pob-market-[a-f0-9]{64}\.snapshot\.[a-f0-9-]{36}\.tmp$/;
const metadataLimit = 1024;

function digest(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function filename(key) {
  return 'pob-market-' + digest(key) + '.snapshot';
}

function readSnapshot(path, maxBodyBytes) {
  const fd = openSync(path, 'r');
  try {
    const info = fstatSync(fd);
    if (!info.isFile() || info.size > maxBodyBytes + metadataLimit) throw new Error('Invalid market snapshot size');
    const raw = Buffer.alloc(info.size);
    if (readSync(fd,raw,0,raw.length,0)!==raw.length || raw[64]!==10) throw new Error('Truncated market snapshot');
    const content = raw.subarray(65);
    if (raw.toString('ascii',0,64)!==digest(content)) throw new Error('Invalid market snapshot checksum');
    const end = content.indexOf(10);
    if (end<1 || end+66>metadataLimit) throw new Error('Invalid market snapshot header');
    return {metadata:JSON.parse(content.toString('utf8',0,end)),body:content.subarray(end+1)};
  } finally {
    closeSync(fd);
  }
}

function openMarketSnapshots(directory, { now, requestKey, validatePayload, validTag, freshnessMs, maxBodyBytes }) {
  const root = resolve(directory);
  const stats = {restored:0, discarded:0, errors:0};
  function removePath(path) {
    try { rmSync(path,{force:true}); }
    catch { stats.errors++; }
  }
  let files;
  try {
    if (!lstatSync(root).isDirectory()) throw new Error('Invalid snapshot directory');
    const contents = readdirSync(root,{withFileTypes:true});
    files = contents.filter(file=>file.isFile() && filenamePattern.test(file.name));
    // A crash between a write and eviction can leave one extra entry.
    if (files.length>96) throw new Error('Too many market snapshot files');
    const probe = join(root,'pob-market-'+randomUUID()+'.probe');
    writeFileSync(probe,'',{flag:'wx',mode:0o600});
    rmSync(probe,{force:true});
    for (const file of contents) {
      if (file.isFile() && temporaryPattern.test(file.name)) removePath(join(root,file.name));
    }
  } catch {
    throw new Error('Cannot open the market snapshot directory. Configure an existing private cache directory.');
  }
  function* entries() {
    const at = now();
    const oldestFirst = files.map(file=>({path:join(root,file.name),name:file.name}))
      .map(file=>{
        try { return {...file,time:lstatSync(file.path).mtimeMs}; }
        catch { return {...file,time:0}; }
      }).sort((a,b)=>a.time-b.time);
    for (const file of oldestFirst) {
      let details, entry;
      try {
        const {metadata,body} = readSnapshot(file.path,maxBodyBytes);
        if (metadata.version!==1 || typeof metadata.key!=='string' || filename(metadata.key)!==file.name) {
          throw new Error('Invalid market snapshot key');
        }
        details = requestKey('/'+metadata.key);
        const {sourceAt, validUntil, ttl, etag} = metadata;
        if (details.key!==metadata.key || body.length>details.limit || !Number.isSafeInteger(sourceAt) ||
            sourceAt<0 || sourceAt>at || at-sourceAt>=freshnessMs || !Number.isFinite(ttl) || ttl<=0 || ttl>300 ||
            !Number.isFinite(validUntil) || validUntil<sourceAt || validUntil>sourceAt+freshnessMs ||
            validUntil>at+ttl*1000 || (etag!==null && !validTag(etag))) {
          throw new Error('Invalid market snapshot freshness or metadata');
        }
        const leagues = validatePayload(JSON.parse(body.toString('utf8')),details.kind);
        entry = {body, leagues, sourceAt, validUntil, etag, ttl, store:true};
      } catch {
        stats.discarded++;
        removePath(file.path);
        continue;
      }
      stats.restored++;
      yield {key:details.key,entry};
    }
  }
  function remove(key) {
    removePath(join(root,filename(key)));
  }
  function save(key, entry) {
    if (!entry.store || entry.ttl<=0) {
      remove(key);
      return;
    }
    const {sourceAt, validUntil, ttl, etag} = entry;
    const header = Buffer.from(JSON.stringify({version:1,key,sourceAt,validUntil,ttl,etag})+'\n');
    const content = Buffer.concat([header,entry.body]);
    const path = join(root,filename(key));
    const temporary = path+'.'+randomUUID()+'.tmp';
    try {
      writeFileSync(temporary,Buffer.concat([Buffer.from(digest(content)+'\n'),content]),{flag:'wx',mode:0o600,flush:true});
      renameSync(temporary,path);
    } catch {
      stats.errors++;
      removePath(path);
    } finally {
      removePath(temporary);
    }
  }
  return {entries,remove,save,health:()=>({...stats})};
}

module.exports = { openMarketSnapshots };
