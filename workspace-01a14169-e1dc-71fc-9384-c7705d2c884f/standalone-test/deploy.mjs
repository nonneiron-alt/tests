import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,existsSync,mkdirSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createInterface} from 'node:readline/promises';

process.chdir(dirname(fileURLToPath(import.meta.url)));
const ROOT=process.cwd();
const GROQ_KEY='gsk_test_not_real';
const name=process.env.KTO_WORKER_NAME||'kto-ty-quiz';
const databaseName=process.env.KTO_DATABASE_NAME||`${name}-db`;
const uuidPattern=/^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i;
const npxCli=join(ROOT,'mock-npx.cjs');
const environment={...process.env,WRANGLER_SEND_METRICS:'false',NO_COLOR:'1'};
if(environment.KTO_ACCOUNT_ID)environment.CLOUDFLARE_ACCOUNT_ID=environment.KTO_ACCOUNT_ID;
function run(args,{capture=false,input,allowFailure=false}={}){
  const result=spawnSync(process.execPath,[npxCli,'--yes','wrangler@4',...args],{
    cwd:ROOT,env:environment,encoding:'utf8',windowsHide:false,
    stdio:input!==undefined?['pipe','inherit','inherit']:capture?['ignore','pipe','pipe']:'inherit',
    input,maxBuffer:32*1024*1024
  });
  if(result.error)throw result.error;
  if(result.status!==0&&!allowFailure){
    if(capture){if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);}
    throw new Error(`Wrangler failed: ${args.join(' ')} (exit ${result.status})`);
  }
  return {ok:result.status===0,stdout:result.stdout||'',stderr:result.stderr||''};
}
function parseJson(text){
  const clean=text.replace(/\u001b\[[0-9;]*m/g,'').trim();
  try{return JSON.parse(clean);}catch{}
  for(let i=0;i<clean.length;i++){
    if(clean[i]!=='['&&clean[i]!=='{')continue;
    for(let j=clean.length;j>i;j--){
      if(clean[j-1]!==']'&&clean[j-1]!=='}')continue;
      try{return JSON.parse(clean.slice(i,j));}catch{}
    }
  }
  throw new Error('Wrangler did not return JSON. Run npx.cmd --yes wrangler@4 d1 list --json to inspect the account.');
}
function findDatabase(value){
  if(!value||typeof value!=='object')return null;
  if(Array.isArray(value)){for(const item of value){const match=findDatabase(item);if(match)return match;}return null;}
  if(value.name===databaseName)return value;
  for(const k of ['result','results','databases','data']){const match=findDatabase(value[k]);if(match)return match;}
  return null;
}
async function getDatabaseList(){
  let result=run(['d1','list','--json'],{capture:true,allowFailure:true});
  if(!result.ok&&!environment.CLOUDFLARE_API_TOKEN){
    console.log('Cloudflare authentication may be required. Complete login in your browser.');
    run(['login']);
    result=run(['d1','list','--json'],{capture:true,allowFailure:true});
  }
  if(!result.ok){
    process.stderr.write(result.stderr||result.stdout);
    if(!environment.CLOUDFLARE_ACCOUNT_ID&&!environment.CI){
      const rl=createInterface({input:process.stdin,output:process.stdout});
      const accountId=(await rl.question('If Cloudflare asks to select an account, paste its Account ID (or Enter to stop): ')).trim();rl.close();
      if(/^[a-f\d]{32}$/i.test(accountId)){
        environment.CLOUDFLARE_ACCOUNT_ID=accountId;
        result=run(['d1','list','--json'],{capture:true,allowFailure:true});
      }
    }
  }
  if(!result.ok)throw new Error('Cannot list D1 databases. Check Cloudflare authorization and account permissions. No database was deleted.');
  return parseJson(result.stdout);
}
async function main(){
  if(!/^[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$/.test(name))throw new Error('Invalid Worker name.');
  if(!/^[a-zA-Z0-9_-]+$/.test(databaseName))throw new Error('Invalid database name.');
  if(!existsSync(npxCli))throw new Error('Portable Node installation is missing npm. Delete .tools/node and run the installer again.');
  console.log('\n[1/5] Cloudflare login and D1 discovery');
  let databaseId=environment.KTO_DATABASE_ID||'';
  if(databaseId&&!uuidPattern.test(databaseId))throw new Error('DatabaseId must be the actual D1 database UUID.');
  // Always verify authentication, even with an explicit database ID.
  let databases=await getDatabaseList();
  if(!databaseId){
    let record=findDatabase(databases);
    if(!record){
      console.log(`Creating D1 database: ${databaseName}`);
      run(['d1','create',databaseName]);
      for(let attempt=0;attempt<4;attempt++){
        databases=parseJson(run(['d1','list','--json'],{capture:true}).stdout);
        record=findDatabase(databases);if(record)break;
        await new Promise(r=>setTimeout(r,1500));
      }
    }
    if(record)for(const field of ['uuid','database_id','id']){
      const candidate=String(record[field]||'').trim();if(uuidPattern.test(candidate)){databaseId=candidate;break;}
    }
    if(!databaseId){
      console.error('Matched database metadata:',record||'not found');
      throw new Error('Cannot determine the D1 UUID. Re-run install.ps1 with -DatabaseId and the real UUID from Cloudflare.');
    }
  }
  console.log(`Using D1: ${databaseName} (${databaseId})`);
  const config={name,main:'worker.js',compatibility_date:'2025-04-01',workers_dev:true,
    assets:{directory:'./static',binding:'ASSETS',run_worker_first:['/api/*']},
    d1_databases:[{binding:'DB',database_name:databaseName,database_id:databaseId,migrations_dir:'migrations'}],
    observability:{enabled:true}};
  if(environment.CLOUDFLARE_ACCOUNT_ID)config.account_id=environment.CLOUDFLARE_ACCOUNT_ID;
  writeFileSync('wrangler.jsonc',JSON.stringify(config,null,2)+'\n');
  console.log('\n[2/5] Applying schema and starter quizzes');
  run(['d1','migrations','apply',databaseName,'--remote','--config','wrangler.jsonc']);
  console.log('\n[3/5] Deploying the site and API');
  run(['deploy','--config','wrangler.jsonc']);
  console.log('\n[4/5] Installing the embedded Groq key as a Worker Secret');
  run(['secret','put','GROQ_API_KEY','--config','wrangler.jsonc'],{input:GROQ_KEY+'\n'});
  console.log('\n[5/5] Done! Open the workers.dev URL shown above.');
  console.log('AI model: openai/gpt-oss-120b. Your key is not sent to visitors.');
  console.log('Running this installer again updates the site without deleting cloud quizzes.');
  console.log('Local SQLite files are NOT imported automatically. Existing D1 data is preserved.');
  console.log(`Project directory: ${ROOT}`);
}
main().catch(error=>{console.error('\nDEPLOY FAILED:',error.message);process.exitCode=1;});
