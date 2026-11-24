#!/usr/bin/env python3
import argparse,json,sys
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--environment',required=True,choices=['RootHide','Rootless'])
p.add_argument('--profile',required=True)
p.add_argument('--output',required=True)
a=p.parse_args()
data=json.loads((Path(__file__).resolve().parents[1]/'Profiles/profiles.json').read_text())
if a.profile=='Auto':
    candidates=[x for x in data['profiles'] if x['environment']==a.environment]
    if len(candidates)!=1:
        print(f'ERROR: no unique registered build profile for {a.environment}; Rootless profile is not verified.',file=sys.stderr); sys.exit(20)
    profile=candidates[0]
else:
    profile=next((x for x in data['profiles'] if x['id']==a.profile),None)
    if profile is None:
        print(f'ERROR: profile {a.profile} is not in the profile registry.',file=sys.stderr); sys.exit(21)
    if profile['environment']!=a.environment:
        print(f'ERROR: profile {a.profile} does not match environment {a.environment}.',file=sys.stderr); sys.exit(22)
Path(a.output).write_text(json.dumps(profile,indent=2)+'\n')
print(f"Resolved profile: {profile['id']} ({profile['environment']})")
