FROM node:24.22.3-alpine3.24@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5

WORKDIR /opt/pob-market
COPY tools/serve_loot_market_cache.cjs tools/loot_market_snapshots.cjs ./
RUN mkdir -p /var/lib/pob-market/snapshots \
    && chown -R node:node /var/lib/pob-market \
    && chmod 700 /var/lib/pob-market /var/lib/pob-market/snapshots

ENV POB_MARKET_CACHE_BIND=0.0.0.0 \
    POB_MARKET_CACHE_PORT=9410 \
    POB_MARKET_COOLDOWN_FILE=/var/lib/pob-market/cooldown \
    POB_MARKET_SNAPSHOT_DIRECTORY=/var/lib/pob-market/snapshots

USER node
EXPOSE 9410
HEALTHCHECK --interval=10s --timeout=4s --start-period=5s CMD ["node", "-e", "fetch('http://127.0.0.1:'+process.env.POB_MARKET_CACHE_PORT+'/health',{signal:AbortSignal.timeout(2000)}).then(async response=>{const health=await response.json();if(!response.ok||health.status!=='ready'||health.provider?.cooldownPersistence!=='ready'||health.snapshots?.errors!==0)process.exitCode=1;}).catch(()=>{process.exitCode=1;})"]
CMD ["node", "serve_loot_market_cache.cjs"]
