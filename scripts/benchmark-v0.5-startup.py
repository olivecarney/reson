#!/usr/bin/env python3
"""Isolated v0.4/v0.5 warm readiness and idle measurements (macOS).
Run library_bench for both versions first, then scripts/build.sh.
Copies sources, injects readiness logging/cache paths only in ignored copies.
Pass a library_bench fixture directory and an archived v0.4 source directory.
Uses only synthetic databases under build/v0.5-bench; never personal data.
"""
from pathlib import Path
import json, os, queue, shutil, sqlite3, statistics, subprocess, sys, threading, time
root=Path.cwd(); databases=(Path(sys.argv[1]) if len(sys.argv)>1 else root/'build/v0.5-bench/library').resolve(); baseline=(Path(sys.argv[2]) if len(sys.argv)>2 else root/'build/v0.5-baseline/src').resolve(); output=root/'build/v0.5-startup'; output.mkdir(parents=True,exist_ok=True)
for label in ['baseline','current']:
    source=baseline if label=='baseline' else root
    folder=output/label/'macos'
    shutil.copytree(source/'macos',folder,ignore=shutil.ignore_patterns('.build','.swiftpm'),dirs_exist_ok=True)
    package=folder/'Package.swift'; package.write_text(package.read_text().replace('"../target/release"','"'+str(source/'target/release')+'"'))
    app=folder/'App/ResonApp.swift';app.write_text(app.read_text().replace('PlayerModel()', 'PlayerModel(settings: UserDefaults(suiteName: \"dev.reson.v05-bench-'+label+'\")!)').replace('import AppKit','import AppKit\nimport Darwin').replace('model.startLibrary() }','model.startLibrary(); DispatchQueue.global().async { print("RESON_WINDOW_READY"); fflush(stdout) } }'))
    model=folder/'App/PlayerModel.swift';model.write_text(model.read_text().replace('import AppKit','import AppKit\nimport Darwin').replace('savedTracks = loaded; updateTracks()','savedTracks = loaded; updateTracks(); DispatchQueue.global().async { print("RESON_LIBRARY_READY"); fflush(stdout) }'))
    cache=folder/'App/Artwork/ArtworkCache.swift';cache.write_text(cache.read_text().replace('static let shared = ArtworkCache()','static let shared = ArtworkCache(directory: URL(fileURLWithPath: "'+str(output/label/'artwork')+'"))'))
    with (output/f'{label}-build.log').open('w') as log:
        subprocess.run(['swift','build','-c','release','--arch','arm64','--package-path',str(folder)],stdout=log,stderr=log,check=True)
    binpath=subprocess.check_output(['swift','build','-c','release','--arch','arm64','--package-path',str(folder),'--show-bin-path'],text=True).strip()
    for count in [270,5000,25000]:
        target=output/label/f'{count}.db'
        fixture=databases/f'{count}.db'; assert fixture.is_file(), fixture
        source_db=sqlite3.connect(f'file:{fixture}?mode=ro',uri=True)
        assert source_db.execute('select count(*) from tracks').fetchone()[0]==count
        dest=sqlite3.connect(target);source_db.backup(dest);source_db.close();dest.close()
        case=[]
        for run in range(6):
            started=time.perf_counter();p=subprocess.Popen([str(Path(binpath)/'Reson')],env={**os.environ,'RESON_LIBRARY_PATH':str(target)},stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
            events=queue.Queue()
            def read():
                for line in p.stdout: events.put((line.strip(),1000*(time.perf_counter()-started)))
            reader=threading.Thread(target=read,daemon=True);reader.start();row={'label':label,'count':count,'run':run}
            try:
                while not all(k in row for k in ['RESON_WINDOW_READY','RESON_LIBRARY_READY']):
                    message,ms=events.get(timeout=20)
                    if message.startswith('RESON_'):row[message]=round(ms,3)
                if run==5:
                    def cpu():
                        parts=subprocess.check_output(['ps','-p',str(p.pid),'-o','time='],text=True).strip().split(':')
                        return float(parts[-1])+60*float(parts[-2])
                    time.sleep(3);a=cpu();start=time.perf_counter();time.sleep(10)
                    row['idle_cpu_percent']=round((cpu()-a)/(time.perf_counter()-start)*100,3)
                    row['rss_kib']=int(subprocess.check_output(['ps','-p',str(p.pid),'-o','rss='],text=True).strip())
                print(json.dumps(row),flush=True);case.append(row)
            finally:
                p.terminate();p.wait(timeout=10);reader.join(timeout=1)
        summary={'label':label,'count':count,'window_median_ms':statistics.median(r['RESON_WINDOW_READY'] for r in case[1:]),'library_median_ms':statistics.median(r['RESON_LIBRARY_READY'] for r in case[1:]),'idle_cpu_percent':case[-1]['idle_cpu_percent'],'rss_kib':case[-1]['rss_kib']}
        print('SUMMARY '+json.dumps(summary),flush=True)
        c=sqlite3.connect(target);print('INTEGRITY',label,count,c.execute('pragma integrity_check').fetchone()[0],'version',c.execute('pragma user_version').fetchone()[0],'track_identity',c.execute('select count(*),min(id),max(id),sum(id) from tracks').fetchone(),flush=True);c.close()
