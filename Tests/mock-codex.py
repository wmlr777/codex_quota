#!/usr/bin/env python3
import json,sys,os
for line in sys.stdin:
    message=json.loads(line)
    method=message['method']
    if method=='initialize':
        assert message['params']['clientInfo']['name']=='codex_quota'
        print(json.dumps({'id':message['id'],'result':{}}),flush=True)
    elif method=='initialized':
        initialized=True
    elif method=='account/rateLimits/read':
        assert initialized
        if os.environ.get('MOCK_FAILURE'):
            print(json.dumps({'id':message['id'],'error':{'code':-1,'message':'auth failed'}}),flush=True)
        else:
            print(json.dumps({'method':'unrelated/notification','params':{}}),flush=True)
            print(json.dumps({'id':message['id'],'result':{'rateLimits':{'primary':{'usedPercent':68},'secondary':None}}}),flush=True)
