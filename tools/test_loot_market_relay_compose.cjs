// cspell:ignore Rootfs
'use strict';

const assert = require('node:assert/strict');
const { execFile, spawnSync } = require('node:child_process');
const { once } = require('node:events');
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { createServer, request } = require('node:http');
const { createServer: createTls } = require('node:https');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');
const { promisify } = require('node:util');
const runFile = promisify(execFile);

const repository = resolve(__dirname,'..');
const feeds = ['Currency','Oil','Omen','Essence','Thread','Fragment','Resonator','Artifact'];
const fixture = `
const original = global.fetch;
global.fetch = async (url, options) => {
  if (url==='http://127.0.0.1:9410/health') return original(url,options);
  const upstream = new URL(url);
  if (upstream.origin!=='https://poe.ninja' || options.redirect!=='error' || !options.headers['User-Agent']) {
    throw new Error('Unexpected provider request');
  }
  if (process.env.POB_RELAY_FIXTURE_MODE==='outage') throw new Error('Fixture provider outage');
  if (upstream.searchParams.get('type')==='Scarab') return new Response(null,{status:429,headers:{'Retry-After':'120'}});
  const data = upstream.pathname.endsWith('/leagues') ? [{id:'Covens',name:'Covens of Umbra'}] :
    {core:{primary:'chaos'},items:[{id:'alt',name:'Orb of Alteration'}],
      lines:[{id:'alt',primaryValue:0.2,volumePrimaryValue:400}]};
  return new Response(JSON.stringify(data),{headers:{date:process.env.POB_RELAY_FIXTURE_DATE,
    'cache-control':'max-age=300',etag:'W/"fixture"'}});
};
`;

function run(file,args,env=process.env) {
  const result = spawnSync(file,args,{cwd:repository,env,encoding:'utf8',timeout:240000,windowsHide:true});
  if (result.error) throw result.error;
  assert.equal(result.status,0,(result.stdout+result.stderr).slice(-5000));
  return result.stdout.trim();
}

async function listen(server) {
  server.listen(0,'127.0.0.1');
  await once(server,'listening');
  return server.address().port;
}

async function close(server) {
  server.closeAllConnections();
  await new Promise(resolve=>server.close(resolve));
}

async function qualify(directory,relayPort) {
  const cert = join(directory,'cert.pem');
  const key = join(directory,'key.pem');
  run('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1',
    '-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1']);
  const proxy = createTls({cert:readFileSync(cert),key:readFileSync(key)},(incoming,outgoing)=>{
    if (incoming.method!=='GET' || !incoming.url?.startsWith('/pob-market/')) {
      outgoing.writeHead(404).end();
      return;
    }
    const forwarded = request({host:'127.0.0.1',port:relayPort,path:incoming.url.slice('/pob-market'.length)},response=>{
      outgoing.writeHead(response.statusCode,response.headers);
      response.pipe(outgoing);
    });
    forwarded.on('error',()=>outgoing.writeHead(502).end());
    forwarded.end();
  });
  try {
    const port = await listen(proxy);
    const {stdout} = await runFile(process.execPath,
      [join(repository,'tools','check_loot_market_cache.cjs'),`https://127.0.0.1:${port}/pob-market/`,'Covens'],{
        cwd:repository,env:{...process.env,NODE_EXTRA_CA_CERTS:cert},timeout:30000,
      });
    return JSON.parse(stdout);
  } finally {
    await close(proxy);
  }
}

async function main() {
  const directory = mkdtempSync(join(tmpdir(),'pob-market-image-'));
  const project = directory.split(/[\\/]/).at(-1).toLowerCase();
  assert.match(project,/^pob-market-image-[a-z0-9]+$/);
  const composePath = join(repository,'deploy','market-relay','compose.yaml');
  const providerPath = join(directory,'provider.cjs');
  const override = join(directory,'fixture.json');
  writeFileSync(providerPath,fixture);
  const temporaryListener = createServer();
  const relayPort = await listen(temporaryListener);
  await close(temporaryListener);
  const env = {...process.env,POB_MARKET_UPSTREAM_AGENT:'PoB container smoke (isolated fixture)',
    POB_MARKET_LOOPBACK_PORT:String(relayPort)};
  const compose = (...args)=>run('docker',['compose','-p',project,'-f',composePath,'-f',override,...args],env);
  const configuration = (mode,date)=>writeFileSync(override,JSON.stringify({services:{'market-relay':{
    environment:{NODE_OPTIONS:'--require=/fixtures/provider.cjs',POB_RELAY_FIXTURE_MODE:mode,POB_RELAY_FIXTURE_DATE:date},
    volumes:[{type:'bind',source:providerPath,target:'/fixtures/provider.cjs',read_only:true}],
  }}}));
  const relay = path=>fetch(`http://127.0.0.1:${relayPort}${path}`,{signal:AbortSignal.timeout(18000)});
  try {
    configuration('warm',new Date().toUTCString());
    compose('build','market-relay');
    const sourceDate = new Date(Date.now()-30000).toUTCString();
    configuration('warm',sourceDate);
    compose('up','-d','--wait','--wait-timeout','60');
    assert.equal(compose('port','market-relay','9410'),`127.0.0.1:${relayPort}`);
    const container = compose('ps','-q','market-relay');
    assert.equal(run('docker',['inspect','--format','{{.Config.User}} {{.HostConfig.ReadonlyRootfs}}',container]),'node true');
    for (const category of feeds) {
      const response = await relay('/exchange/current/overview?league=Covens&type='+category);
      assert.equal(response.status,200);
      assert.equal(response.headers.get('date'),sourceDate);
      assert.equal((await response.json()).core.primary,'chaos');
    }
    const warm = await (await relay('/health')).json();
    assert.equal(warm.requests,9);
    assert.equal(warm.cached,9);
    const limited = await relay('/exchange/current/overview?league=Covens&type=Scarab');
    assert.equal(limited.status,429);
    assert.equal(limited.headers.get('retry-after'),'120');

    configuration('outage',sourceDate);
    compose('up','-d','--force-recreate','--wait','--wait-timeout','60');
    assert.notEqual(compose('ps','-q','market-relay'),container);
    const report = await qualify(directory,relayPort);
    assert.equal(report.status,'passed');
    assert.equal(report.probes.length,10);
    assert.deepEqual(report.probes[0].snapshots,{restored:9,discarded:0,errors:0});
    assert.equal(report.probes[0].provider.state,'cooldown');
    assert.ok(report.probes[0].provider.cooldownSeconds>0);
    assert.ok(report.probes.slice(1).every(probe=>probe.freshnessSeconds>=30));
    const held = await relay('/exchange/current/overview?league=Covens&type=Scarab');
    assert.equal(held.status,429);
    assert.ok(Number(held.headers.get('retry-after'))>0);
    assert.equal((await (await relay('/health')).json()).requests,0);
    console.log('Market relay image restored nine responses and the provider cooldown, then passed ten HTTPS probes without upstream requests.');
  } finally {
    compose('down','--volumes','--rmi','local');
    rmSync(directory,{recursive:true,force:true});
  }
}

main().catch(error=>{console.error(error.stack);process.exitCode=1;});
