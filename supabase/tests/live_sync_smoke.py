"""Explicit production smoke test: creates two anonymous fixtures and deletes them.
Uses only the public client key. Never uses existing users or broadcasts pushes.
Usage: python3 live_sync_smoke.py --config /path/to/Secrets.xcconfig
"""
import argparse, base64, datetime, json, re, urllib.error, urllib.request, uuid
from pathlib import Path


def run(config):
    source = Path(config).read_text()
    host = re.search(r'[a-z]{20}\.supabase\.co', source).group()
    key = re.search(r'^SUPABASE_ANON_KEY\s*=\s*(\S+)', source, re.M).group(1)
    sessions, checks = [], []

    def call(path, method='GET', token=None, body=None, headers=None):
        h = {'apikey': key, 'Authorization': 'Bearer ' + (token or key)}
        if headers: h.update(headers)
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
            h['Content-Type'] = 'application/json'
        request = urllib.request.Request('https://' + host + path, data=body, headers=h, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                status, data = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, data = error.code, error.read()
        try: data = json.loads(data)
        except (json.JSONDecodeError, UnicodeDecodeError): pass
        return status, data

    def expect(label, status, allowed):
        if status not in allowed: raise AssertionError(f'{label}: HTTP {status}, expected {allowed}')
        checks.append(label)

    try:
        for _ in range(2):
            status, session = call('/auth/v1/signup', 'POST', body={})
            expect('create anonymous fixture', status, [200])
            sessions.append(session)
        a, b = sessions
        uid, token = a['user']['id'], a['access_token']
        btoken = b['access_token']
        now = datetime.datetime.now(datetime.timezone.utc)
        fresh = now.isoformat()
        old = (now-datetime.timedelta(days=1)).isoformat()
        tables = {
            'user_preferences': {'user_id': uid, 'steps_target': 9876, 'sleep_target': 8,
                'modern_palette_categories': ['pastel'], 'allowed_canvas_fills': ['flat'], 'updated_at': fresh},
            'user_daily_stats': {'user_id': uid, 'day_key': 'smoke-test', 'steps_count': 123,
                'sleep_hours': 8, 'base_energy': 20, 'bonus_energy': 0, 'remaining_balance': 20, 'updated_at': fresh},
            'user_daily_spent': {'user_id': uid, 'day_key': 'smoke-test', 'total_spent': 3,
                'spent_by_app': {}, 'updated_at': fresh},
            'user_daily_selections': {'user_id': uid, 'day_key': 'smoke-test',
                'activity_ids': [], 'recovery_ids': [], 'joys_ids': [], 'updated_at': fresh},
            'user_day_canvases': {'user_id': uid, 'day_key': 'smoke-test',
                'canvas_json': {'review_marker': 'fresh'}, 'last_modified': fresh},
        }
        for table, row in tables.items():
            conflict = 'user_id' if table == 'user_preferences' else 'user_id,day_key'
            status, _ = call(f'/rest/v1/{table}?on_conflict={conflict}', 'POST', token, row,
                             {'Prefer':'resolution=merge-duplicates,return=representation'})
            expect('write '+table, status, [200,201])
            status, result = call(f'/rest/v1/{table}?user_id=eq.{uid}&select=*', token=token)
            expect('read '+table, status, [200])
            assert len(result)==1, table+' round trip missing row'
            for k,v in row.items():
                if k not in ['updated_at','last_modified']: assert result[0][k]==v, table+'.'+k
            status, result = call(f'/rest/v1/{table}?user_id=eq.{uid}&select=*', token=btoken)
            assert status==200 and result==[], table+' leaked fixture to other user'
            checks.append('RLS isolation '+table)
        addition_id=str(uuid.uuid4())
        addition={'id':addition_id,'user_id':uid,'day_key':'smoke-yesterday',
                  'option_id':'smoke-happening','color_hex':'#123456',
                  'asset_variant':2,'created_at':old}
        endpoint='/rest/v1/user_happening_additions?on_conflict=id'
        for _ in range(2):
            status,_=call(endpoint,'POST',token,addition,{'Prefer':'resolution=merge-duplicates'})
            expect('historical addition idempotent upsert',status,[200,201])
        query=f'/rest/v1/user_happening_additions?id=eq.{addition_id}'
        _,result=call(query,token=token)
        assert len(result)==1 and result[0]['day_key']=='smoke-yesterday' and result[0]['asset_variant']==2
        checks.append('historical addition payload round trip')
        status,_=call(query,'DELETE',btoken)
        expect('foreign addition delete has no access',status,[200,204])
        _,result=call(query,token=token)
        assert len(result)==1,'foreign caller deleted addition'
        status,_=call(query,'DELETE',token)
        expect('owner explicit addition delete',status,[200,204])
        _,result=call(query,token=token)
        assert result==[],'owner addition delete failed'
        # Simulate a pre-version row after migration. A legitimate queued edit
        # predating deployment must be accepted, then protected against older ones.
        for table, value_key, value in [
            ('user_daily_stats','steps_count',456),
            ('user_daily_spent','total_spent',7),
            ('user_daily_selections','activity_ids',['smoke-new'])
        ]:
            row=dict(tables[table],day_key='smoke-version-baseline',updated_at='1970-01-01T00:00:00Z')
            endpoint=f'/rest/v1/{table}?on_conflict=user_id,day_key'
            status,_=call(endpoint,'POST',token,row,{'Prefer':'resolution=merge-duplicates'})
            expect('create unversioned baseline '+table,status,[200,201])
            row.update({value_key:value,'updated_at':old})
            status,_=call(endpoint,'POST',token,row,{'Prefer':'resolution=merge-duplicates'})
            expect('predeployment queued edit '+table,status,[200,201])
            query=f'/rest/v1/{table}?user_id=eq.{uid}&day_key=eq.smoke-version-baseline&select={value_key}'
            _,result=call(query,token=token)
            assert result[0][value_key]==value,table+' dropped predeployment edit'
            row.update({value_key:tables[table][value_key],'updated_at':(now-datetime.timedelta(days=2)).isoformat()})
            status,_=call(endpoint,'POST',token,row,{'Prefer':'resolution=merge-duplicates'})
            expect('older daily replay '+table,status,[200,201])
            _,result=call(query,token=token)
            assert result[0][value_key]==value,table+' accepted older replay'
            checks.append('version baseline and stale guard '+table)
        status,_=call('/functions/v1/send-push','GET')
        expect('send-push worker method guard',status,[405])
        status,_=call('/functions/v1/send-push','POST',body={})
        expect('send-push public caller forbidden',status,[401])
        stale = dict(tables['user_preferences'],steps_target=1,updated_at=old)
        status,_=call('/rest/v1/user_preferences?on_conflict=user_id','POST',token,stale,{'Prefer':'resolution=merge-duplicates'})
        expect('stale preference accepted as no-op',status,[200,201])
        _, result=call(f'/rest/v1/user_preferences?user_id=eq.{uid}&select=steps_target',token=token)
        assert result[0]['steps_target']==9876, 'stale retry overwrote preferences'
        checks.append('stale preference preserved')
        stale_canvas=dict(tables['user_day_canvases'],canvas_json={'review_marker':'stale'},last_modified=old)
        status,_=call('/rest/v1/user_day_canvases?on_conflict=user_id,day_key','POST',token,stale_canvas,{'Prefer':'resolution=merge-duplicates'})
        expect('stale canvas accepted as no-op',status,[200,201])
        _, result=call(f'/rest/v1/user_day_canvases?user_id=eq.{uid}&select=canvas_json',token=token)
        assert result[0]['canvas_json']['review_marker']=='fresh','stale canvas overwrote artwork'
        checks.append('stale canvas preserved')
        status,_=call(f'/rest/v1/users?id=eq.{uid}','PATCH',token,{'nickname':'integration-smoke','country':'RS'})
        expect('own nickname/country update',status,[200,204])
        status,_=call(f'/rest/v1/users?id=eq.{uid}','PATCH',token,{'is_banned':False})
        expect('ban mutation forbidden',status,[401,403])
        pixel=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII=')
        path=f'/storage/v1/object/avatars/{uid}.jpg'
        status,_=call(path,'POST',token,pixel,{'Content-Type':'image/png','x-upsert':'true'})
        expect('own avatar upload',status,[200])
        status,_=call(path,'POST',btoken,pixel,{'Content-Type':'image/png','x-upsert':'true'})
        expect('other user avatar overwrite denied',status,[400,401,403])
        status,_=call('/storage/v1/object/avatars','DELETE',btoken,{'prefixes':[uid+'.jpg']})
        expect('other user delete request handled without access',status,[200,400,401,403])
        status,_=call('/storage/v1/object/public/avatars/'+uid+'.jpg',token=token)
        expect('avatar survives foreign deletion',status,[200])
        status,_=call('/functions/v1/delete-user','GET',token)
        expect('delete-user GET rejected',status,[405])
        print(json.dumps({'project':host,'checks_passed':checks},indent=2))
    finally:
        failures=[]
        for session in sessions:
            status,_=call('/functions/v1/delete-user','POST',session['access_token'])
            if status!=200: failures.append({'id':session['user']['id'],'status':status})
        if failures:
            Path('/tmp/nowhere-smoke-cleanup-needed.json').write_text(json.dumps(failures))
            raise AssertionError('Fixture cleanup failed; ids saved to /tmp/nowhere-smoke-cleanup-needed.json')
        print('All temporary accounts deleted via deployed delete-user.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True)
    run(parser.parse_args().config)
