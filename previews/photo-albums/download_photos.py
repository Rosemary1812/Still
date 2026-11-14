import concurrent.futures,json,subprocess
from pathlib import Path
root=Path(__file__).parent
ids=['1470770841072-f978cf4d019e','1464822759023-fed622ff2c3b','1501785888041-af3ef285b470','1441974231531-c6227db76b6e','1472396961693-142e6e269027','1447752875215-b2761acb3c5d','1518837695005-2083093ee35b','1469474968028-56623f02e42e','1475924156734-496f6cac6ec1','1500534623283-312aade485b7','1441716844725-09cedc13a4e7','1433086966358-54859d0ed716','1470071459604-3b5ec3a7fe05','1501854140801-50d01698950b','1519681393784-d120267933ba','1426604966848-d7adac402bff']
def get(pair):
 i,p=pair; url=f'https://images.unsplash.com/photo-{p}?w=1200&q=85&fit=max';out=root/'assets'/f'photo-{i}.jpg'
 subprocess.run(['curl','-L','--fail','--silent','--show-error','--retry','1','--max-time','30',url,'-o',str(out)],check=True)
 if not out.read_bytes().startswith(b'\xff\xd8'):raise ValueError(f'not jpeg {i}')
 print(f'photo-{i} ready',flush=True)
 return {'file':f'assets/photo-{i}.jpg','source':url,'provider':'Unsplash'}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(get,enumerate(ids)))
(root/'photo-sources.json').write_text(json.dumps(results,indent=2))
print('16 photographs ready')
