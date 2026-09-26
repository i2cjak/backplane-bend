# Voice

Dictation into the composer, and a Pebble Index ring's voice notes, with
OpenAI's GPT-Live-Transcribe (`gpt-live-transcribe`, the Realtime API's
low-latency transcription model) and a personal dictionary.

## Pieces

- `tools/voice/` builds `backplane-voice` (Bun), the one part that is not
  Bend: it records the microphone (`pw-record`, `parecord` or `arecord`,
  24 kHz mono PCM), streams it to `wss://…/v1/realtime?intent=transcription`
  and prints NDJSON events. It also transcribes a finished recording
  (`file`: ffmpeg to PCM, then the same socket; `gpt-transcribe` over REST
  when ffmpeg is missing). Its README has the protocol.
- `src/server/voice.bend`: the key, the dictionary, live sessions, a ring's
  recording. `server.bend`'s `VoiceJob` answers `bots.voice` requests
  (`op`: status, key, unkey, dict, add, start, stop, devices).
- `src/core/voice.bend` (pure, laws `voice_*`): the dictionary, and which
  words of a transcript to ask about (`Voice.unsure`): a near miss of a
  dictionary term (one word, or two heard for one term: "key cad" for
  KiCad), or a technical-looking word nobody taught it (letters and digits
  mixed, all caps, inner capitals). At most five.
- `src/core/client.bend`'s `Voice`: the session as the client shows it,
  and the clarify actions. The window draws it in `layout.bend` (`Vx.*`,
  `Set.voice`), the web in `view.bend` (`View.voice`, `View.voice.set`).

## Storage

- The key: `<home>/secrets/openai.key` (0600). The helper reads the file
  (`--key-file`), so it is never in an argv, an environment, the event log
  or a message; clients see it masked (`sk-…WXYZ`).
- The dictionary: `<home>/voice/dictionary.txt`, a term a line; it is the
  helper's `keywords`.
- The microphone: the setting `voice.device` ("" for the default source).
- A live session's pid: `<home>/voice/live.pid`. A stop signals it only
  while `ps` says it is still `backplane-voice`.

## Dictating

The mic button beside the paperclip asks the hub to record its own
machine's microphone into the selected thread. The hub sends
`{"t":"voice","thread","ev",…}` to that client only: `live` (recorder,
device, label), `part` (words so far), `text` (a finished segment and its
`unsure` words), `level` (0..100, four times a second), `hint`
(`no-audio` 3 s without bytes, `silent` 4 s without speech, `ok` once
speech comes), `stopping`, `error`, and `idle` last. Nothing is sent until
the person sends it.

Each segment goes into the thread's draft where the caret is (the end, in
the web client or for a thread not on screen) and reads on from what is
there (`Voice.put`): a space before it unless the draft ends in a space, a
new line or a bracket, one after it when a word follows. Mid-sentence, its
first word loses the capital the transcriber gives every segment, unless it
is "I", not a plain word (USB, KiCad), or opens with a dictionary term (the
hub marks those `firm`); before a lower-case word its closing period goes.
The caret moves past it, ctrl+z takes it back out, and the window writes
the draft down as typing does.

The helper opens the recorder and the OpenAI session at once: `live` goes
out as soon as the microphone gives audio (waiting at most 150 ms more for
its name, and sent again with the name if that comes later), and what is
heard before the session opens is kept and sent the moment it does.

The words to clarify show one at a time above the composer: use the guess,
Fix… (type the right spelling: it replaces the word and joins the
dictionary), add the word as heard to the dictionary, or skip it (not asked
again this session).

## A Pebble ring

Set the ring's webhook (docs/bots.md) to send the recording (or both).
Forms may be 2 MB. A form with an `audio` part (M4A) that is let in (its
bearer token, or its Index signature, checked over the body's bytes) is
answered 202 at once; the recording is transcribed with the dictionary and
deleted, and the bot gets Backplane's words, with the words it may have
misheard, instead of the ring's own transcription. With no key, or no
words, the ring's transcription goes as before. A bot can add a term the
person confirms with `voice_dictionary_add`.

## Platforms

Recording uses PipeWire, PulseAudio or ALSA tools, so dictation works on
Linux. The ring's recordings work wherever the hub runs.
