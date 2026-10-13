import subprocess,time,threading,queue,os,json
root=os.getcwd()
for label,exe,db in [('v0.1.1','build/baseline-macos/.build/out/Products/Release/Reson',None),('v0.2-270','build/Reson.app/Contents/MacOS/Reson','build/library-bench/270.db'),('v0.2-25000','build/Reson.app/Contents/MacOS/Reson','build/library-bench/25000.db')]:
 for n in range(6):
  env=os.environ.copy()
  if db: env['RESON_LIBRARY_PATH']=root+'/'+db
  t=time.perf_counter();p=subprocess.Popen([root+'/'+exe],env=env,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
  messages=queue.Queue()
  def read():
   for line in p.stdout:
    messages.put((line.strip(),(time.perf_counter()-t)*1000))
  reader=threading.Thread(target=read,daemon=True);reader.start();result={'label':label,'run':n}
  try:
   while 'RESON_WINDOW_READY' not in result or (db and 'RESON_LIBRARY_READY' not in result):
    message,ms=messages.get(timeout=15)
    if message.startswith('RESON_'):result[message]=round(ms,3)
   if n==5:
    time.sleep(2)
    result['ps']=subprocess.check_output(['ps','-p',str(p.pid),'-o','rss=,%cpu=,time='],text=True).strip()
    subprocess.run(['sample',str(p.pid),'1','-file',root+'/build/'+label+'-idle.txt'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
   print(json.dumps(result),flush=True)
  finally:
   p.terminate();p.wait(timeout=10);reader.join(timeout=1)
