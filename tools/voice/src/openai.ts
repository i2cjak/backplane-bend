// OpenAI speech to text: the Realtime transcription session
// (gpt-live-transcribe) and the REST batch endpoint (gpt-transcribe).

export const LIVE_MODEL = "gpt-live-transcribe";
export const FILE_MODEL = "gpt-transcribe";
export const DELAYS = ["minimal", "low", "medium", "high", "xhigh"];

export type Opts = {
  key: string;
  base: string; // e.g. https://api.openai.com/v1, no trailing slash
  prompt: string;
  keywords: string[];
  languages: string[];
  delay: string;
};

export function baseUrl(env = process.env): string {
  return (env.OPENAI_BASE_URL || "https://api.openai.com/v1").replace(/\/+$/, "");
}

export function wsUrl(base: string): string {
  return base.replace(/^http/, "ws") + "/realtime?intent=transcription";
}

export function sessionUpdate(o: Opts) {
  const t: Record<string, unknown> = { model: LIVE_MODEL };
  if (o.prompt) t.prompt = o.prompt;
  if (o.keywords.length) t.keywords = o.keywords;
  if (o.languages.length) t.languages = o.languages;
  if (o.delay) t.delay = o.delay;
  return {
    type: "session.update",
    session: {
      type: "transcription",
      audio: {
        input: {
          format: { type: "audio/pcm", rate: 24000 },
          transcription: t,
          turn_detection: null,
        },
      },
    },
  };
}

// Why a connection failed, in words: a WebSocket upgrade refusal carries no
// status in Bun, so ask a cheap REST endpoint whether the key is the reason.
async function whyRefused(o: Opts): Promise<string> {
  try {
    const r = await fetch(o.base + "/models", {
      headers: { Authorization: `Bearer ${o.key}` },
      signal: AbortSignal.timeout(5000),
    });
    if (r.status === 401) return "OpenAI rejected the API key (401)";
    if (r.status === 403) return "the API key may not use this model (403)";
    if (r.status === 429) return "OpenAI rate limit or quota exceeded (429)";
  } catch (e) {
    return `could not reach OpenAI: ${msg(e)}`;
  }
  return "could not open the OpenAI realtime session";
}

export function msg(e: unknown): string {
  return (e instanceof Error ? e.message : String(e)).split("\n")[0];
}

export type RtHooks = {
  delta?: (item: string, text: string) => void;
  done?: (item: string, text: string) => void;
  error?: (message: string) => void;
  closed?: () => void;
};

export class Realtime {
  ws: WebSocket;
  hooks: RtHooks;
  commits = 0; // commits sent
  settled = 0; // commits answered (completed, failed, or refused)
  order: string[] = []; // item ids in commit order
  texts = new Map<string, string>();
  open = true;
  private waiters: (() => void)[] = [];

  private constructor(ws: WebSocket, hooks: RtHooks) {
    this.ws = ws;
    this.hooks = hooks;
    ws.onmessage = (m) => this.onMessage(m.data);
    ws.onclose = () => {
      this.open = false;
      this.wake();
      this.hooks.closed?.();
    };
  }

  // Connects and sends the session update; rejects with a human message.
  static async connect(o: Opts, hooks: RtHooks): Promise<Realtime> {
    const ws = await new Promise<WebSocket>((ok, no) => {
      let ws: WebSocket;
      try {
        ws = new WebSocket(wsUrl(o.base), {
          headers: { Authorization: `Bearer ${o.key}` },
        } as any);
      } catch (e) {
        no(e);
        return;
      }
      const timer = setTimeout(() => {
        ws.close();
        no(new Error("timeout"));
      }, 15000);
      ws.onopen = () => {
        clearTimeout(timer);
        ok(ws);
      };
      ws.onerror = ws.onclose = () => {
        clearTimeout(timer);
        no(new Error("refused"));
      };
    }).catch(async () => {
      throw new Error(await whyRefused(o));
    });
    ws.onerror = null;
    const rt = new Realtime(ws, hooks);
    rt.send(sessionUpdate(o));
    return rt;
  }

  send(ev: unknown) {
    if (this.open) this.ws.send(JSON.stringify(ev));
  }

  append(pcm: Uint8Array) {
    this.send({ type: "input_audio_buffer.append", audio: Buffer.from(pcm.buffer, pcm.byteOffset, pcm.length).toString("base64") });
  }

  commit() {
    this.commits++;
    this.send({ type: "input_audio_buffer.commit", event_id: `commit-${this.commits}` });
  }

  clear() {
    this.send({ type: "input_audio_buffer.clear" });
  }

  // Resolves true once every commit is answered, false on timeout or close.
  waitAll(ms: number): Promise<boolean> {
    return new Promise((ok) => {
      const check = () => {
        if (this.settled >= this.commits) return ok(true), true;
        if (!this.open) return ok(false), true;
        return false;
      };
      if (check()) return;
      const t = setTimeout(() => ok(this.settled >= this.commits), ms);
      const w = () => {
        if (check()) clearTimeout(t);
        else this.waiters.push(w);
      };
      this.waiters.push(w);
    });
  }

  // The finished transcripts in commit order.
  joined(): string {
    const ids = [...this.order, ...[...this.texts.keys()].filter((k) => !this.order.includes(k))];
    return ids.map((k) => (this.texts.get(k) ?? "").trim()).filter(Boolean).join(" ");
  }

  close() {
    this.open = false;
    try {
      this.ws.close();
    } catch {}
  }

  private wake() {
    const ws = this.waiters;
    this.waiters = [];
    for (const w of ws) w();
  }

  private onMessage(data: unknown) {
    let ev: any;
    try {
      ev = JSON.parse(String(data));
    } catch {
      return;
    }
    switch (ev?.type) {
      case "input_audio_buffer.committed":
        if (ev.item_id && !this.order.includes(ev.item_id)) this.order.push(ev.item_id);
        break;
      case "conversation.item.input_audio_transcription.delta":
        this.hooks.delta?.(String(ev.item_id ?? ""), String(ev.delta ?? ""));
        break;
      case "conversation.item.input_audio_transcription.completed": {
        const id = String(ev.item_id ?? "");
        const text = String(ev.transcript ?? "");
        this.texts.set(id, text);
        this.settled++;
        this.hooks.done?.(id, text);
        this.wake();
        break;
      }
      case "conversation.item.input_audio_transcription.failed":
        this.settled++;
        this.hooks.error?.(ev.error?.message ?? "transcription failed");
        this.wake();
        break;
      case "error": {
        // a refused commit (e.g. an empty buffer) is answered by this error
        if (String(ev.error?.event_id ?? "").startsWith("commit-")) this.settled++;
        this.hooks.error?.(ev.error?.message ?? "OpenAI error");
        this.wake();
        break;
      }
    }
  }
}

function restError(status: number, body: string): string {
  if (status === 401) return "OpenAI rejected the API key (401)";
  let m = "";
  try {
    m = JSON.parse(body)?.error?.message ?? "";
  } catch {}
  return `OpenAI answered ${status}${m ? `: ${m}` : ""}`;
}

// POST /audio/transcriptions with gpt-transcribe. Keywords and language
// hints go as repeated keywords[] / languages[] fields; a 400 about them
// retries once without them.
export async function transcribeFile(o: Opts, audio: Blob, name: string, signal?: AbortSignal): Promise<string> {
  const post = async (hints: boolean) => {
    const f = new FormData();
    f.append("file", audio, name);
    f.append("model", FILE_MODEL);
    f.append("response_format", "json");
    if (o.prompt) f.append("prompt", o.prompt);
    if (hints) {
      for (const k of o.keywords) f.append("keywords[]", k);
      for (const l of o.languages) f.append("languages[]", l);
    }
    return fetch(o.base + "/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${o.key}` },
      body: f,
      signal,
    });
  };
  const hinted = o.keywords.length > 0 || o.languages.length > 0;
  let r = await post(hinted);
  let body = await r.text();
  if (r.status === 400 && hinted && /keyword|language/i.test(body)) {
    process.stderr.write(`backplane-voice: retrying without keywords/languages: ${body.slice(0, 200)}\n`);
    r = await post(false);
    body = await r.text();
  }
  if (!r.ok) throw new Error(restError(r.status, body));
  try {
    return String(JSON.parse(body).text ?? "");
  } catch {
    throw new Error("OpenAI answered with no transcript");
  }
}
