import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

// Execute the actual handler with network/admin surfaces replaced by a recorder.
function loadHandler() {
  let handler;
  const calls = [];
  const admin = {
    auth: { getUser: async () => ({data: {user: {id: 'caller'}}, error: null}),
      admin: {deleteUser: async id => { calls.push(['auth-delete', id]); return {error:null}; }} },
    storage: {from: () => ({remove: async paths => {calls.push(['avatar-delete',paths]); return {error:null};}})},
    from: () => ({delete: () => ({eq: async (_,id) => {calls.push(['profile-delete',id]);return {error:null};}})})
  };
  const source = readFileSync(new URL('../functions/delete-user/index.ts', import.meta.url),'utf8')
    .replace(/^import .*;\n/gm, '');
  const serve = fn => { handler = fn; };
  vm.runInNewContext(stripTypeScriptTypes(source), {serve, createClient: () => admin, Deno:{env:{get:()=> 'test'},serve}, Response, console});
  return {handler,calls};
}
for (const method of ['GET','DELETE','PUT']) {
  test(`${method} never deletes account even with a valid bearer`, async () => {
    const {handler,calls}=loadHandler();
    const response=await handler(new Request('https://example.test',{method,headers:{Authorization:'Bearer valid'}}));
    assert.equal(response.status,405);
    assert.equal(calls.length,0);
  });
}
test('POST requires a bearer',async()=>{
  const {handler,calls}=loadHandler();
  assert.equal((await handler(new Request('https://example.test',{method:'POST'}))).status,401);
  assert.equal(calls.length,0);
});
test('POST deletes only authenticated caller, ignoring a forged body user id',async()=>{
  const {handler,calls}=loadHandler();
  const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer valid'},body:JSON.stringify({user_id:'victim'})}));
  assert.equal(response.status,200);
  assert.deepEqual(JSON.parse(JSON.stringify(calls)),[['avatar-delete',['caller.jpg']],['profile-delete','caller'],['auth-delete','caller']]);
});
