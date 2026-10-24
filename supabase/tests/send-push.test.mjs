import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {setImmediate} from 'node:timers/promises';
function loadHandler(overrides={}, dependencies={}){
  let handler;
  const env={SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'server-only',APNS_BUNDLE_ID:'test.bundle', ...overrides};
  const source=stripTypeScriptTypes(readFileSync(new URL('../functions/send-push/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
  vm.runInNewContext(source,{Deno:{env:{get:k=>env[k]},serve:fn=>{handler=fn;}},Response,TextEncoder,console,
    createClient:()=>{throw Error('Unauthorized path reached database');},fetch:()=>{throw Error('Tests must never send push');}, ...dependencies});
  return handler;
}
for(const auth of [undefined,'Bearer anon-public-key','Bearer server-only-extra']){
  test('broadcast rejects non-admin bearer '+String(auth),async()=>{
    const r=await loadHandler()(new Request('https://example.test',{method:'POST',headers:auth?{Authorization:auth}:{},body:'{}'}));
    assert.equal(r.status,401);
  });
}
test('broadcast GET is rejected without reading tokens',async()=>{
  assert.equal((await loadHandler()(new Request('https://example.test',{headers:{Authorization:'Bearer server-only'}}))).status,405);
});
test('admin malformed body rejected before reading tokens',async()=>{
  assert.equal((await loadHandler()(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer server-only'},body:'bad json'}))).status,400);
});

test('missing APNs configuration does not crash method/auth guards',async()=>{
  const handler=loadHandler({APNS_BUNDLE_ID:undefined});
  assert.equal((await handler(new Request('https://example.test'))).status,405);
  assert.equal((await handler(new Request('https://example.test',{method:'POST',body:'{}'}))).status,401);
});
test('admin request without APNs configuration fails closed before reading tokens',async()=>{
  const handler=loadHandler({APNS_BUNDLE_ID:undefined});
  const r=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer server-only'},body:JSON.stringify({title:'test',body:'test'})}));
  assert.equal(r.status,503);
});
test('admin JSON null is a bad request',async()=>{
  const r=await loadHandler()(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer server-only'},body:'null'}));
  assert.equal(r.status,400);
});

// Exercise the full authorized handler and real JWT generation; only database
// transport and APNs HTTP are substituted. No test can call a production host.
const keyPair = await webcrypto.subtle.generateKey({name:'ECDSA', namedCurve:'P-256'}, true, ['sign','verify']);
const privateKey = await webcrypto.subtle.exportKey('pkcs8', keyPair.privateKey);
const apnsEnv = {APNS_TEAM_ID:'test-team', APNS_KEY_ID:'test-key',
  APNS_PRIVATE_KEY:`-----BEGIN PRIVATE KEY-----\n${Buffer.from(privateKey).toString('base64')}\n-----END PRIVATE KEY-----`};
function broadcastFixture(count, {cap=1000, failPage=0, failureToken}={}) {
  const rows = Array.from({length:count}, (_, i)=>({id:String(i+1).padStart(8,'0'), token:`test-token-${i}`}));
  // Deliberately scrambled storage order; production must request stable order.
  const storage = [...rows].reverse();
  const delivered = [], deleted = [];
  let reads=0, exhausted=false, active=0, peak=0;
  const client = {from(table) {
    assert.equal(table,'device_tokens');
    let after, limit=Infinity, ordered=false, platform;
    const query = {
      select(){return query;},
      eq(column,value){assert.equal(column,'platform'); platform=value; return query;},
      order(column,options){assert.equal(column,'id'); assert.equal(options?.ascending,true); ordered=true; return query;},
      gt(column,value){assert.equal(column,'id'); after=value; return query;},
      limit(value){limit=value; return query;},
      delete(){return {in:async(column,tokens)=>{assert.equal(column,'token'); deleted.push(...tokens); return {error:null};}};},
      then(resolve,reject){
        reads++;
        assert.equal(platform,'ios');
        if(reads===failPage) return Promise.resolve({data:null,error:{message:'private database detail'}}).then(resolve,reject);
        let data=(ordered ? rows : storage).filter(row=>!after || row.id>after).slice(0,Math.min(cap,limit));
        if(data.length===0) exhausted=true;
        return Promise.resolve({data,error:null}).then(resolve,reject);
      },
    };
    return query;
  }};
  const handler=loadHandler(apnsEnv, {createClient:()=>client, crypto:webcrypto, btoa, atob,
    fetch:async(url)=>{
      assert.equal(exhausted,true,'all token pages must be read before any delivery');
      assert.match(url,/^https:\/\/api\.push\.apple\.com\/3\/device\/test-token-\d+$/);
      const token=url.split('/').at(-1);
      delivered.push(token); active++; peak=Math.max(peak,active);
      await setImmediate(); active--;
      return token===failureToken ? new Response(JSON.stringify({reason:'BadDeviceToken'}),{status:400}) : new Response(null,{status:200});
    }});
  return {rows, delivered, deleted, get reads(){return reads;}, get peak(){return peak;},
    run:()=>handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer server-only'},
      body:JSON.stringify({title:'Fixture',body:'Fixture'})}))};
}
for(const count of [0,999,1000,1001,2001]) {
  test(`broadcast visits every token exactly once across API pages: ${count}`,async()=>{
    const fixture=broadcastFixture(count);
    const response=await fixture.run();
    assert.equal(response.status,200);
    const result=await response.json();
    assert.equal(result.sent,count);
    if(count) {assert.equal(result.total,count); assert.equal(result.failed,0);}
    assert.deepEqual(fixture.delivered,fixture.rows.map(row=>row.token));
    assert.ok(fixture.peak<=50,'APNs concurrency must remain bounded');
    assert.equal(fixture.reads,Math.ceil(count/1000)+1);
  });
}
test('broadcast continues when actual API cap is below requested page size',async()=>{
  const fixture=broadcastFixture(1001,{cap:137});
  const response=await fixture.run();
  assert.equal((await response.json()).total,1001);
  assert.deepEqual(fixture.delivered,fixture.rows.map(row=>row.token));
  assert.equal(fixture.reads,9);
});
for(const failPage of [1,2,3]) {
  test(`page ${failPage} failure reports database error before sending any notification`,async()=>{
    const fixture=broadcastFixture(2001,{failPage});
    const response=await fixture.run();
    assert.equal(response.status,500);
    assert.deepEqual(await response.json(),{error:'Database error'});
    assert.deepEqual(fixture.delivered,[]);
  });
}
test('paginated broadcast preserves APNs failure counts and invalid-token cleanup',async()=>{
  const fixture=broadcastFixture(1001,{failureToken:'test-token-1000'});
  const response=await fixture.run();
  assert.deepEqual(await response.json(),{sent:1000,failed:1,cleaned:1,topic_mismatches:0,total:1001});
  assert.deepEqual(fixture.deleted,['test-token-1000']);
});
