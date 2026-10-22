import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

// Execute the actual handler with network/admin surfaces replaced by a recorder.
function loadHandler({ avatarErrors = [], profileErrors = [], authErrors = [] } = {}) {
  let handler;
  const calls = [];
  const admin = {
    auth: { getUser: async () => ({data: {user: {id: 'caller'}}, error: null}),
      admin: {deleteUser: async id => { calls.push(['auth-delete', id]); return {error:authErrors.shift() ?? null}; }} },
    storage: {from: () => ({remove: async paths => {calls.push(['avatar-delete',paths]); return {data:[],error:avatarErrors.shift() ?? null};}})},
    from: () => ({delete: () => ({eq: async (_,id) => {calls.push(['profile-delete',id]);return {error:profileErrors.shift() ?? null};}})})
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

function deleteRequest() {
  return new Request('https://example.test', {
    method: 'POST', headers: { Authorization: 'Bearer valid' }
  });
}

for (const stage of ['avatar', 'profile']) {
  test(`${stage} cleanup failure preserves auth identity and allows retry`, async () => {
    const { handler, calls } = loadHandler({
      [`${stage}Errors`]: [{ message: 'Temporary cleanup failure' }, null]
    });
    const failed = await handler(deleteRequest());
    assert.equal(failed.status, 500);
    assert.equal((await failed.json()).success, undefined);
    assert.equal(calls.some(([operation]) => operation === 'auth-delete'), false);
    if (stage === 'avatar') {
      assert.equal(calls.some(([operation]) => operation === 'profile-delete'), false);
    }

    calls.length = 0;
    const retried = await handler(deleteRequest());
    assert.equal(retried.status, 200);
    assert.equal((await retried.json()).success, true);
    assert.deepEqual(calls.map(([operation]) => operation),
      ['avatar-delete', 'profile-delete', 'auth-delete']);
  });
}

test('auth deletion failure reports failure and can retry after cleanup already succeeded', async () => {
  const { handler, calls } = loadHandler({ authErrors: [{ message: 'Temporary auth failure' }, null] });
  const failed = await handler(deleteRequest());
  assert.equal(failed.status, 500);
  assert.equal((await failed.json()).success, undefined);
  calls.length = 0;
  const retried = await handler(deleteRequest());
  assert.equal(retried.status, 200);
  assert.equal((await retried.json()).success, true);
  assert.deepEqual(calls.map(([operation]) => operation),
    ['avatar-delete', 'profile-delete', 'auth-delete']);
});
