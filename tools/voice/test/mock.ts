// A local stand-in for the OpenAI API: the realtime transcription socket and
// POST /audio/transcriptions. Only the key "good" is accepted.

export type Mock = {
  base: string;
  ws: any[]; // every client event received over the socket
  rest: FormData[]; // every transcription request
  opts: { rejectHints?: boolean; refuseWs?: boolean };
  stop: () => void;
};

export function startMock(opts: Mock["opts"] = {}): Mock {
  const m: Mock = { base: "", ws: [], rest: [], opts, stop: () => {} };
  const authed = (req: Request) => req.headers.get("authorization") === "Bearer good";
  const server = Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    async fetch(req, srv) {
      const u = new URL(req.url);
      if (!authed(req)) return Response.json({ error: { message: "Incorrect API key" } }, { status: 401 });
      if (u.pathname === "/v1/realtime") {
        if (m.opts.refuseWs || u.searchParams.get("intent") !== "transcription") return new Response("no", { status: 500 });
        if (srv.upgrade(req, { data: { bytes: 0, n: 0 } })) return;
        return new Response("upgrade failed", { status: 400 });
      }
      if (u.pathname === "/v1/models") return Response.json({ data: [] });
      if (u.pathname === "/v1/audio/transcriptions" && req.method === "POST") {
        const f = await req.formData();
        m.rest.push(f);
        if (m.opts.rejectHints && (f.getAll("keywords[]").length || f.getAll("languages[]").length)) {
          return Response.json({ error: { message: "Unrecognized request argument supplied: keywords" } }, { status: 400 });
        }
        const file = f.get("file") as Blob;
        return Response.json({ text: `rest ${file.size} bytes` });
      }
      return new Response("not found", { status: 404 });
    },
    websocket: {
      message(ws: any, raw) {
        const ev = JSON.parse(String(raw));
        m.ws.push(ev);
        const d = ws.data as { bytes: number; n: number };
        if (ev.type === "input_audio_buffer.append") d.bytes += Buffer.from(ev.audio, "base64").length;
        if (ev.type === "input_audio_buffer.clear") d.bytes = 0;
        if (ev.type === "input_audio_buffer.commit") {
          if (d.bytes < 4800) {
            ws.send(JSON.stringify({ type: "error", error: { message: "buffer too small", event_id: ev.event_id } }));
            return;
          }
          const id = `item_${++d.n}`;
          const text = `seg${d.n} ${Math.round(d.bytes / 48)}ms`;
          d.bytes = 0;
          ws.send(JSON.stringify({ type: "input_audio_buffer.committed", item_id: id }));
          ws.send(JSON.stringify({ type: "conversation.item.input_audio_transcription.delta", item_id: id, delta: `seg${d.n}` }));
          setTimeout(() => {
            ws.send(JSON.stringify({ type: "conversation.item.input_audio_transcription.delta", item_id: id, delta: text.slice(`seg${d.n}`.length) }));
            ws.send(JSON.stringify({ type: "conversation.item.input_audio_transcription.completed", item_id: id, transcript: text }));
          }, 50);
        }
      },
    },
  });
  m.base = `http://127.0.0.1:${server.port}/v1`;
  m.stop = () => server.stop(true);
  return m;
}
