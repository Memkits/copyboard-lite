import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
const run=(...args)=>execFileSync(process.env.COPYBOARD_QUERY_CLI||'calcit',args,{encoding:'utf8',maxBuffer:10e6,stdio:['ignore','pipe','pipe']});
function normalizeSets(value){
  if(Array.isArray(value))return value.map(normalizeSets);
  if(value&&typeof value==='object'){
    const result=Object.fromEntries(Object.entries(value).map(([k,v])=>[k,normalizeSets(v)]));
    if(Object.keys(result).length===1&&Array.isArray(result.__edn_set))result.__edn_set.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
    return result;
  }
  return value;
}
const q=(...args)=>normalizeSets(JSON.parse(run('query',...args,'--format','json')).data);
mkdirSync('acceptance',{recursive:true});
function inventory(){
  const defs=[];
  for(const ns of q('ns').namespaces){
    const names=run('query','defs',ns).split('\n').filter(x=>/^  \S/.test(x)).map(x=>x.trim().split(' ')[0]);
    assert.equal(names.length,q('ns',ns).definition_count);
    for(const name of names)defs.push(q('def',ns+'/'+name));
  }
  return defs;
}
const aliases={'option:unwrap':'.unwrap','option:unwrap-or':'.unwrap-or','option:some?':'.some?','count':'.len'};
function select(defs,check){
  const ops=[],counts={};
  function walk(node,path,id){
    if(!Array.isArray(node))return;
    if(['quote','quasiquote',';','comment','defmacro'].includes(node[0]))return;
    if(Object.hasOwn(aliases,node[0])){
      const old=node[0];assert.equal(node.length,old==='option:unwrap-or'?3:2);
      if(old==='count')assert.ok(['app.lite/submit-content!','app.lite/link-href'].includes(id));
      const p='@'+[...path,0].join('.');
      if(check)assert.equal(JSON.parse(run('tree','show',id,'--path',p,'--format','json')).tree,old);
      ops.push(['tree','replace',id,'--path',p,'--input-format','json-ast','--code',JSON.stringify(aliases[old]),'--expect','quote '+old]);
      counts[old]=(counts[old]||0)+1;node[0]=aliases[old];
    }
    node.forEach((child,i)=>walk(child,[...path,i],id));
  }
  defs.forEach(def=>walk(def.code,[],def.id));return {ops,counts};
}
if(process.argv[2]==='inventory'){
  const defs=inventory();writeFileSync('acceptance/reviewed.json',JSON.stringify(defs,null,2));
  console.log(JSON.stringify({definitions:defs.length,tests:defs.reduce((n,d)=>n+d.tests.length,0),counts:select(structuredClone(defs),false).counts}));process.exit(0);
}
assert.equal(run('-v').trim(),'0.30.1');run('docs','agents','--contract');
const before=inventory(),config=q('config'),namespaces=q('ns').namespaces.map(ns=>q('ns',ns));
assert.deepEqual(before,normalizeSets(JSON.parse(readFileSync('acceptance/reviewed.json','utf8'))));
writeFileSync('acceptance/content-type.json',run('query','type-at','app.lite/submit-content!','--path','@3.2.1.1.1','--format','json'));
const expected=structuredClone(before),{ops,counts}=select(expected,true);
assert.deepEqual(counts,{'option:unwrap':20,'option:unwrap-or':6,'option:some?':5,'count':2});assert.equal(ops.length,33);
const boundaries=[['app.lite/login!',[4,1,1,2,1],'username-input'],['app.lite/login!',[4,1,1,3,1],'password-input'],['app.lite/submit-content!',[3,1,1,1],'input']];
for(const [id,path,variable] of boundaries){
  const def=expected.find(d=>d.id===id);let parent=def.code;
  for(const i of path.slice(0,-1))parent=parent[i];
  assert.deepEqual(parent[path.at(-1)],['.unwrap-or',['js-nullish->option',[variable,':value']],'|']);
  const replacement=['browser/element-value',variable];parent[path.at(-1)]=replacement;
  ops.push(['tree','replace',id,'--path','@'+path.join('.'),'--input-format','json-ast','--code',JSON.stringify(replacement),'--expect',`.unwrap-or (js-nullish->option (${variable} :value)) |`]);
}
writeFileSync('acceptance/before.json',JSON.stringify(before,null,2));
writeFileSync('acceptance/operations.json',JSON.stringify(ops,null,2));writeFileSync('acceptance/counts.json',JSON.stringify(counts,null,2));
const args=['edit','transaction','--file','acceptance/operations.json','--format','json'];
const preview=JSON.parse(run(...args,'--dry-run'));assert.ok(preview.scoped_revision);
writeFileSync('acceptance/preview.json',JSON.stringify(preview,null,2));writeFileSync('acceptance/applied.json',run(...args,'--expect-revision',preview.scoped_revision));
assert.deepEqual(inventory(),expected);assert.deepEqual(q('config'),config);
writeFileSync('acceptance/content-type-after.json',run('query','type-at','app.lite/submit-content!','--path','@3.2.1.1.1','--format','json'));
assert.deepEqual(q('ns').namespaces.map(ns=>q('ns',ns)),namespaces);
writeFileSync('acceptance/after.json',JSON.stringify(expected,null,2));
writeFileSync('acceptance/snapshot-blob.txt',execFileSync('git',['hash-object','calcit.cirru'],{encoding:'utf8'}));
console.log(JSON.stringify({guardedDefinitions:before.length,operations:ops.length,counts,checkedDomReads:3,unchanged:'all other arguments/defaults/schemas/FFI/metadata/imports/config and all attached tests/examples'}));
