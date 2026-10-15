#!/bin/bash
set -euo pipefail
release_root="$(cd "$(dirname "$0")/.." && pwd)"
"$release_root/OneWayMac/build.sh"
python3 - "$release_root" <<'PY'
from pathlib import Path
import datetime,plistlib,subprocess,sys
root=Path(sys.argv[1]); archive=root/'.build/release/JustThirty-Mac.xcarchive'
app=root/'OneWayMac/.build/JustThirty.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
(archive/'Products/Applications').mkdir(parents=True,exist_ok=True)
subprocess.run(['ditto',str(app),str(archive/'Products/Applications/JustThirty.app')],check=True)
(archive/'dSYMs').mkdir(exist_ok=True)
for name in ['JustThirty.app.dSYM','OneWayHelper.dSYM']:
 subprocess.run(['ditto',str(root/'OneWayMac/.build'/name),str(archive/'dSYMs'/name)],check=True)
metadata={'ArchiveVersion':2,'CreationDate':datetime.datetime.now(datetime.timezone.utc),'Name':'JustThirty','SchemeName':'JustThirty','ApplicationProperties':{'ApplicationPath':'Applications/JustThirty.app','Architectures':['arm64','x86_64'],'CFBundleIdentifier':info['CFBundleIdentifier'],'CFBundleShortVersionString':info['CFBundleShortVersionString'],'CFBundleVersion':info['CFBundleVersion']}}
(archive/'Info.plist').write_bytes(plistlib.dumps(metadata))
print(f'Prepared Mac archive: {archive}')
PY
cat <<'HELP'
Open the archive in Xcode. Choose Distribute App > Direct Distribution to
notarize with your signed-in Apple account. This does not publish an App Store
listing. Wait for Accepted, then use Export Notarized App. Verify the exported
bundle with stapler and Gatekeeper before sharing it.
HELP
