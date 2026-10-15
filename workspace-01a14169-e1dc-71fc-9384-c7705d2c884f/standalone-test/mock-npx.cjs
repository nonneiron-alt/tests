const fs=require('fs');const a=process.argv.slice(2);const cmd=a.slice(2);const mode=process.env.TEST_SCENARIO||'existing';
if(cmd[0]==='d1'&&cmd[1]==='list'){
 let rec={name:'kto-ty-quiz-db',uuid:'d131aedd-d5be-48cb-897f-f6c3d5819086'};
 if(mode==='id'){rec.database_id=rec.uuid;delete rec.uuid}
 if(mode==='new'&&!fs.existsSync('created.flag')){console.log('[]');process.exit(0)}
 console.log(JSON.stringify({result:[[{name:'unrelated',uuid:'85dd0e7c-c06f-4b27-a919-6c5727bcb668'},rec]]}));
}else if(cmd[0]==='d1'&&cmd[1]==='create'){fs.writeFileSync('created.flag','1');console.log('Created database');}
else if(cmd[0]==='secret'){
 const input=fs.readFileSync(0,'utf8').trim();if(input!=='gsk_test_not_real')process.exit(1);console.log('Secret received through stdin (not printed)');
}else console.log('Mock Wrangler:',cmd.join(' '));
