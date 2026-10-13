#!/usr/bin/env python3
"""Build isolated readiness-instrumented Swift copies and compare v0.2.0.

Requires scripts/build.sh and isolated 270.db/25000.db under
build/v0.2.1-smoke (see docs/validation-v0.2.1.md). Never modifies production
sources or personal library data. Run from the repository root.
"""
from pathlib import Path
import subprocess, shutil
root=Path.cwd()
for label in ['v02','v021']:
 folder=root/'build'/f'startup-{label}'/'macos'
 folder.mkdir(parents=True,exist_ok=True)
 if label=='v02':
  paths=subprocess.check_output(['git','ls-tree','-r','--name-only','v0.2.0','macos'],text=True).splitlines()
  for p in paths:
   dest=folder/Path(p).relative_to('macos');dest.parent.mkdir(parents=True,exist_ok=True)
   dest.write_bytes(subprocess.check_output(['git','show','v0.2.0:'+p]))
 else:
  for name in ['App','Views','Bridge','Tests']:
   shutil.copytree(root/'macos'/name,folder/name,dirs_exist_ok=True)
  for name in ['Package.swift','Info.plist']:shutil.copy2(root/'macos'/name,folder/name)
 package=folder/'Package.swift';package.write_text(package.read_text().replace('"../target/release"','"'+str(root/'target/release')+'"'))
 app=folder/'App/ResonApp.swift';app.write_text(app.read_text().replace('import AppKit','import AppKit\nimport Darwin').replace('model.startLibrary() }','model.startLibrary(); DispatchQueue.global().async { print("RESON_WINDOW_READY"); fflush(stdout) } }'))
 model=folder/'App/PlayerModel.swift';model.write_text(model.read_text().replace('import AppKit','import AppKit\nimport Darwin').replace('savedTracks = loaded; updateTracks()','savedTracks = loaded; updateTracks(); DispatchQueue.global().async { print("RESON_LIBRARY_READY"); fflush(stdout) }'))
 with open(root/'build'/f'startup-{label}-build.log','w') as log:
  subprocess.run(['swift','build','-c','release','--package-path',str(folder)],stdout=log,stderr=log,check=True)

from pathlib import Path
import subprocess,time,os,json,queue,threading,statistics
root=Path.cwd()
result=[]
def cpu(pid):
 parts=subprocess.check_output(['ps','-p',str(pid),'-o','time='],text=True).strip().split(':')
 return float(parts[-1])+60*float(parts[-2])
for label in ['v02','v021']:
 folder=root/'build'/f'startup-{label}'/'macos'
 binpath=subprocess.check_output(['swift','build','-c','release','--package-path',str(folder),'--show-bin-path'],text=True).strip()
 for count in [270,25000]:
  case=[]
  for n in range(6):
   env=os.environ.copy();env['RESON_LIBRARY_PATH']=str(root/'build/v0.2.1-smoke'/f'{count}.db')
   start=time.perf_counter();p=subprocess.Popen([str(Path(binpath)/'Reson')],env=env,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
   messages=queue.Queue()
   def reader():
    for line in p.stdout:messages.put((line.strip(),(time.perf_counter()-start)*1000))
   thread=threading.Thread(target=reader,daemon=True);thread.start();row={'label':label,'tracks':count,'run':n}
   try:
    while 'RESON_WINDOW_READY' not in row or 'RESON_LIBRARY_READY' not in row:
     message,ms=messages.get(timeout=15)
     if message.startswith('RESON_'):row[message]=round(ms,3)
    if n==5:
     time.sleep(3)
     a=cpu(p.pid);t=time.perf_counter();time.sleep(10);b=cpu(p.pid)
     row['idle_cpu_percent']=round((b-a)/(time.perf_counter()-t)*100,3)
     row['ps']=subprocess.check_output(['ps','-p',str(p.pid),'-o','rss=,%cpu=,time='],text=True).strip()
     footprint=root/'build'/f'{label}-{count}-footprint.txt'
     with open(footprint,'w') as f:subprocess.run(['/usr/bin/footprint','-p',str(p.pid)],stdout=f,stderr=f)
    print(json.dumps(row),flush=True);case.append(row)
   finally:p.terminate();p.wait(timeout=10);thread.join(timeout=1)
  print('MEDIAN',label,count,'window',statistics.median(r['RESON_WINDOW_READY'] for r in case[1:]),'library',statistics.median(r['RESON_LIBRARY_READY'] for r in case[1:]),flush=True)
