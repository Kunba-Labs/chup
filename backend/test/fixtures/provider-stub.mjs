// Test child process only: no traffic reaches OpenAI.
globalThis.fetch = async (_url, options) => new Promise((_resolve,reject)=>{
 process.send?.('provider-started');
 options.signal.addEventListener('abort',()=>{process.send?.('provider-aborted');reject(new DOMException('Aborted','AbortError'));},{once:true});
});
