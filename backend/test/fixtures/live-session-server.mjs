// Explicit test fixture: localhost only, no upstream and no microphone access.
import http from 'node:http';
import {WebSocketServer} from 'ws';
const server=http.createServer();
const sockets=new WebSocketServer({server});
sockets.on('connection',(socket,request)=>{
  if(request.headers.authorization!=='Bearer native-fixture-only'){socket.close();return;}
  const send=event=>socket.send(JSON.stringify(event));
  send({type:'session.started',session:{id:'fixture-live-session'}});
  let sent=false;
  socket.on('message',data=>{
    const event=JSON.parse(data);
    if(['session.input_audio.mute','session.input_audio.unmute'].includes(event.type)) {
      send({type:event.type==='session.input_audio.mute'?'session.input_audio.muted':'session.input_audio.unmuted',client_event_id:event.event_id});
    }
    if(event.type==='session.input_audio.append'&&!sent&&Buffer.from(event.audio,'base64').some(value=>value!==0)){
      sent=true;
      send({type:'session.delegation.created',delegation:{id:'fixture-delegation'}});
      send({type:'session.input_transcript.delta',delta:'What did we decide?',start_ms:0,end_ms:20});
    }
    if(event.type==='session.commentary.append'){
      if(event.delegation_id!=='fixture-delegation'){send({type:'error',error:{message:'Wrong delegation scope'}});return;}
      send({type:'session.output_transcript.delta',delta:event.content,start_ms:20,end_ms:40});
      send({type:'session.output_audio.delta',event_id:'fixture-audio',delta:Buffer.alloc(960,1).toString('base64')});
    }
    if(event.type==='session.close'){
      send({type:'session.closed',usage:{fixture:true,duration_seconds:1}});socket.close();
    }
  });
});
server.listen(0,'127.0.0.1',()=>console.log(server.address().port));
