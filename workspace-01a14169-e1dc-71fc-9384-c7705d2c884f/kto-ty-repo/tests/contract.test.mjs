import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker.js';

// Offline contract tests only. These are NOT evidence of real model quality.
test('catalog returns D1 quizzes',async()=>{
  const rows=[{id:'gnome',title:'Какой ты гном?'}];
  const env={DB:{prepare:()=>({all:async()=>({results:rows})})}};
  const res=await worker.fetch(new Request('https://test.invalid/api/quizzes'),env);
  assert.equal(res.status,200);assert.deepEqual(await res.json(),rows);
});
test('too short topic is rejected before writing',async()=>{
  const env={DB:{prepare(){throw Error('Unexpected SQL');}}};
  const req=new Request('https://test.invalid/api/create',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:'x'})});
  const res=await worker.fetch(req,env);assert.equal(res.status,400);
});
test('cross-origin POST is rejected',async()=>{
  const res=await worker.fetch(new Request('https://test.invalid/api/create',{method:'POST',headers:{Origin:'https://elsewhere.invalid'},body:'{}'}),{DB:{}});
  assert.equal(res.status,403);
});
test('final Groq request contains the topic and all five answers',async()=>{
  const oldFetch=globalThis.fetch;
  const previous=Array.from({length:4},(_,i)=>({question:`Вопрос ${i+1}`,answer:`Ответ ${i+1}`}));
  const state={answers:previous,current:{question:'Вопрос 5',options:['А','Б','В','Г']}};
  const row={id:'a'.repeat(32),quiz_id:'gnome',title:'Какой ты гном?',history:JSON.stringify(state),result:null};
  let payload;
  const result={title:'Ты — гном-хранитель',subtitle:'Тестовая заглушка',emoji:'🍄',paragraphs:['Первый абзац','Второй абзац','Третий абзац'],traits:[],image_query:'forest',image_kind:'forest'};
  globalThis.fetch=async(url,init)=>{
    if(String(url).startsWith('https://api.groq.com/')){payload=JSON.parse(init.body);return Response.json({choices:[{message:{content:JSON.stringify(result)}}]});}
    return Response.json({query:{pages:{}}});
  };
  const env={GROQ_API_KEY:'offline-test-placeholder',DB:{
    prepare(sql){return {sql,bind(...args){this.args=args;return this;},first:async()=>row};},
    batch:async()=>[{meta:{changes:1}},{meta:{changes:1}}]
  }};
  try{
    const res=await worker.fetch(new Request('https://test.invalid/api/answer',{method:'POST',body:JSON.stringify({session:row.id,answer:'Ответ 5'})}),env);
    assert.equal(res.status,200);
    const task=JSON.parse(payload.messages[1].content);
    assert.equal(task.topic,row.title);
    assert.equal(task.answers.length,5);
    assert.equal(task.answers[4].question,'Вопрос 5');
    assert.equal(task.answers[4].answer,'Ответ 5');
    assert.equal(payload.model,'openai/gpt-oss-120b');
    assert.equal((await res.json()).result.title,result.title);
  }finally{globalThis.fetch=oldFetch;}
});

test.todo('P0: reject or regenerate structurally valid but off-topic results');
test.todo('P0: Genshin results must name a real Genshin character, not a generic archetype');
test.todo('P0: numeric topic "Сколько в тебе котов?" must produce an actual quantity');
