"""Independent Cartesian-product oracle plus full CLI/trace integration checks."""
import argparse, itertools, json, random, subprocess, tempfile
from pathlib import Path
from verify import check

def oracle(problem):
    # Enumerate the full product in source order; no planner ordering or pruning.
    capacities={b['id']:int(b['capacity']) for b in problem['banks']}
    choices=[]
    for b in problem['buffers']:
        banks=[b['fixed_bank']] if b.get('fixed_bank') is not None else b['banks']
        slots=[]
        for bank in banks:
            maximum=capacities[bank]-int(b['bytes'])
            offsets=[int(b['fixed_offset'])] if b.get('fixed_offset') is not None else range(0,maximum+1,int(b['alignment']))
            slots.extend((bank,offset) for offset in offsets if 0<=offset<=maximum)
        choices.append(slots)
    for placement in itertools.product(*choices):
        valid=True
        for i,(bank,offset) in enumerate(placement):
            a=problem['buffers'][i]
            for j in range(i):
                other_bank,other_offset=placement[j];b=problem['buffers'][j]
                if bank!=other_bank or a['last']<b['first'] or b['last']<a['first']:continue
                if offset<int(b['bytes'])+other_offset and other_offset<int(a['bytes'])+offset:
                    valid=False;break
            if not valid:break
        if valid:return True
    return False

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--exe',required=True);ap.add_argument('--trace-exe',required=True);ap.add_argument('--cases',type=int,default=160)
    args=ap.parse_args();root=Path(__file__).resolve().parents[1];exe=str(Path(args.exe).resolve());trace_exe=str(Path(args.trace_exe).resolve())
    cli_calls=0
    def run(argv,expected=0):
        nonlocal cli_calls
        cli_calls+=1
        p=subprocess.run([exe,*map(str,argv)],capture_output=True,text=True,encoding='utf8',timeout=20)
        assert p.returncode==expected,(argv,p.returncode,p.stdout,p.stderr)
        if p.stdout.lstrip().startswith(('{','[')):return json.loads(p.stdout)
        return p.stdout
    tempbase=Path('D:/Dev/Temp') if Path('D:/Dev/Temp').is_dir() else root/'.tools/temporary'
    tempbase.mkdir(parents=True,exist_ok=True)
    solved=infeasible=0
    with tempfile.TemporaryDirectory(prefix='arena-extensions-',dir=tempbase) as temporary:
        work=Path(temporary);assert work.resolve().is_relative_to(tempbase.resolve())
        case=work/'case.json';layout_file=work/'layout.json'
        for seed in range(args.cases):
            rng=random.Random(seed)
            p={'schema':1,'banks':[{'id':f'bank{k}','capacity':str(rng.randrange(2,8))} for k in range(rng.randrange(1,3))],'buffers':[]}
            bank_ids=[b['id'] for b in p['banks']]
            for i in range(rng.randrange(1,4)):
                first=rng.randrange(3)
                b={'id':f'b{i}','bytes':str(rng.randrange(1,5)),'alignment':str(rng.choice([1,2,4])),'first':first,'last':first+rng.randrange(2),'banks':rng.sample(bank_ids,rng.randrange(1,len(bank_ids)+1))}
                if rng.randrange(5)==0:b.update(fixed_bank=b['banks'][0],fixed_offset=str(rng.randrange(3)*int(b['alignment'])))
                p['buffers'].append(b)
            expected=oracle(p);case.write_text(json.dumps(p),encoding='utf8')
            result=run(['exact',case,'1000000'],0 if expected else 1)
            assert result['status']==('solved' if expected else 'infeasible'),(seed,result)
            if expected:
                solved+=1;check(p,result['layout'])
                layout_file.write_text(json.dumps(result['layout']),encoding='utf8')
                assert run(['verify',case,layout_file])['valid']
            else:infeasible+=1
        assert solved>0 and infeasible>0
        witness=root/'examples/exact_alignment.json'
        greedy=run(['plan',witness],1);assert int(greedy['banks'][0]['highwater'])==12
        exact=run(['exact',witness]);assert exact['status']=='solved'
        layout_file.write_text(json.dumps(exact['layout']),encoding='utf8')
        peaks=run(['explain',witness,layout_file]);assert int(peaks[0]['highwater'])==9
        peaks=run(['explain',witness],1);assert int(peaks[0]['layout_over_budget_by'])==3 and int(peaks[0]['live_over_budget_by'])==0
        limited=run(['exact',witness,'1'],3);assert limited['status']=='limit' and 'layout' not in limited
        run(['exact',witness,'0'],2)
        run(['exact',witness,'10','extra'],2)
        run(['explain',witness,layout_file,'extra'],2)
        kib=root/'examples/exact_alignment_kib.json'
        kib_greedy=run(['plan',kib],1);assert int(kib_greedy['banks'][0]['highwater'])==12288
        kib_exact=run(['exact',kib]);check(json.loads(kib.read_text(encoding='utf8')),kib_exact['layout'])
        layout_file.write_text(json.dumps(kib_exact['layout']),encoding='utf8')
        assert int(run(['explain',kib,layout_file])[0]['highwater'])==9216
        before=root/'examples/regression_before.json';after=root/'examples/regression_after.json'
        default=run(['compare',before,after],1);assert not default['gate_passed']
        assert run(['compare',before,after,'16384'])['gate_passed']
        assert run(['compare',after,before])['gate_passed']
        run(['compare',before,after,'-1'],2)
        # Actual executed C producer -> typed trace -> problem -> layout -> C header.
        captured=json.loads(subprocess.check_output([trace_exe],text=True,encoding='utf8',timeout=20))
        trace_file=work/'trace.json';trace_file.write_text(json.dumps(captured),encoding='utf8')
        p=run(['trace',trace_file]);assert [(b['first'],b['last']) for b in p['buffers']]==[(0,1),(1,2),(2,3)]
        case.write_text(json.dumps(p),encoding='utf8');report=run(['plan',case]);check(p,report['layout'])
        assert int(report['banks'][0]['highwater'])==48
        layout_file.write_text(json.dumps(report['layout']),encoding='utf8')
        header=run(['header',case,layout_file]);(root/'examples/c_replay/generated_plan.h').write_text(header,encoding='utf8')
        captured['events'].append({'step':4,'op':'read','buffer':'a'})
        trace_file.write_text(json.dumps(captured),encoding='utf8');run(['trace',trace_file],2)
    result={'cartesian_oracle_cases':args.cases,'solved':solved,'infeasible':infeasible,'cli_calls':cli_calls,'trace_buffers':3,'trace_events':12,'trace_plan_highwater':48,'greedy_alignment_highwater':12,'exact_alignment_highwater':9,'greedy_alignment_kib':12,'exact_alignment_kib':9,'status':'passed'}
    artifact=root/'artifacts';artifact.mkdir(exist_ok=True);(artifact/'extensions.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
