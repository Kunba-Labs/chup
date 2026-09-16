// Runs only in the contract-test child process. It never reaches an external provider.
globalThis.fetch = async (url, options) => {
  if (url.endsWith('/audio/transcriptions')) {
    const form = options.body;
    if (form.get('model') !== 'gpt-4o-transcribe-diarize' || form.get('response_format') !== 'diarized_json' || form.get('chunking_strategy') !== 'auto' || form.getAll('known_speaker_names[]').join() !== 'voice_a' || !form.get('known_speaker_references[]').startsWith('data:audio/wav;base64,')) throw new Error('Incorrect provider multipart contract');
    return Response.json({text:'A test utterance',segments:[{start:0,end:2,text:'A test utterance',speaker:'voice_a'}]});
  }
  const body = JSON.parse(options.body);
  const schema = body.text.format.name;
  const result = schema === 'dictation_fidelity' ? {valid:false} : {text:'We agreed on 12 September.'};
  return Response.json({output:[{content:[{type:'output_text',text:JSON.stringify(result)}]}]});
};
