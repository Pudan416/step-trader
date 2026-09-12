import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
function loadHandler(overrides={}){
  let handler;
  const env={SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'server-only',APNS_BUNDLE_ID:'test.bundle', ...overrides};
  const source=stripTypeScriptTypes(readFileSync(new URL('../functions/send-push/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/gm,''));
  vm.runInNewContext(source,{Deno:{env:{get:k=>env[k]},serve:fn=>{handler=fn;}},Response,TextEncoder,console,
    createClient:()=>{throw Error('Unauthorized path reached database');},fetch:()=>{throw Error('Tests must never send push');}});
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
