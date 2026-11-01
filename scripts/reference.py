"""Run unchanged upstream TFLM greedy code with build-only logging/status shims."""
import argparse,base64,hashlib,json,os,subprocess,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
HARNESS='#include <cstdio>\n#include <cstddef>\n#include "tensorflow/lite/micro/memory_planner/greedy_memory_planner.h"\nint main() {\n  alignas(16) unsigned char scratch[4096];\n  tflite::micro::GreedyMemoryPlanner a;\n  if (a.Init(scratch,sizeof(scratch))!=kTfLiteOk) return 2;\n  for (int i=0;i<3;i++) if (a.AddBuffer(64,2*i,2*i+1)!=kTfLiteOk) return 3;\n  printf("{\\"reuse\\":%zu,",a.GetMaximumMemorySize());\n  tflite::micro::GreedyMemoryPlanner b;\n  if(b.Init(scratch,sizeof(scratch))!=kTfLiteOk) return 2;\n  b.AddBuffer(64,0,1);b.AddBuffer(64,1,2);\n  printf("\\"handover\\":%zu,",b.GetMaximumMemorySize());\n  tflite::micro::GreedyMemoryPlanner c;\n  c.Init(scratch,sizeof(scratch));c.AddBuffer(128,0,3);c.AddBuffer(128,1,2);\n  printf("\\"single_arena_concurrent\\":%zu}\\n",c.GetMaximumMemorySize());\n}\n'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--cxx',default='cl' if os.name=='nt' else 'c++');args=parser.parse_args()
    dest=ROOT/'.tools/tflm-reference';dest.mkdir(parents=True,exist_ok=True)
    inventory=json.loads((ROOT/'docs/REFERENCE_FILES.json').read_text())
    for name,meta in inventory.items():
        p=dest/name;p.parent.mkdir(parents=True,exist_ok=True)
        if p.exists():data=p.read_bytes()
        else:
            headers={'User-Agent':'MoonArenaPlan-reference-check'}
            if os.environ.get('GH_TOKEN'):headers['Authorization']='Bearer '+os.environ['GH_TOKEN']
            url='https://api.github.com/repos/tensorflow/tflite-micro/git/blobs/'+meta['git_blob_sha']
            with urllib.request.urlopen(urllib.request.Request(url,headers=headers),timeout=30) as response:blob=json.load(response)
            data=base64.b64decode(blob['content'])
            p.write_bytes(data)
        assert hashlib.sha256(data).hexdigest()==meta['sha256'],name
        assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==meta['git_blob_sha'],name
    shims={
      'tensorflow/lite/micro/compatibility.h':'#pragma once\n#define TF_LITE_REMOVE_VIRTUAL_DELETE\n',
      'tensorflow/lite/micro/micro_common.h':'#pragma once\n#include <cstddef>\nenum TfLiteStatus { kTfLiteOk = 0, kTfLiteError = 1 };\n',
      'tensorflow/lite/micro/micro_log.h':'#pragma once\ninline void MicroPrintf(const char*, ...) {}\n',
      'main.cc':HARNESS}
    for name,content in shims.items():
        p=dest/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(content,encoding='utf8',newline='\n')
    executable=dest/('reference.exe' if os.name=='nt' else 'reference')
    if os.name=='nt':cmd=[args.cxx,'/nologo','/EHsc','/std:c++14','/I'+str(dest),str(dest/'main.cc'),str(dest/'greedy.cc'),'/Fe:'+str(executable),'/Fo:'+str(dest)+os.sep]
    else:cmd=[args.cxx,'-std=c++14','-I',str(dest),str(dest/'main.cc'),str(dest/'greedy.cc'),'-o',str(executable)]
    subprocess.run(cmd,check=True,cwd=dest)
    result=json.loads(subprocess.check_output([str(executable)],text=True))
    assert result=={'reuse':64,'handover':128,'single_arena_concurrent':256},result
    result['scope']='upstream planner algorithm with minimal build-only ABI/logging shims; not full TFLM runtime'
    out=ROOT/'artifacts';out.mkdir(exist_ok=True);(out/'reference.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
