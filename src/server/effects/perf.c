// Performance counters
// ====================
//
// The raw sink behind src/server/perf.bend. Any computation in the process
// (the hub, the window, a connection) records a value under a name in
// nanoseconds of work: a count, a sum, a max, the last value and a log2
// histogram (bucket i holds values in [2^(i-1), 2^i), bucket 0 holds 0).
// Everything else (means, percentiles, rates, the report, the overlay) is
// Bend, in src/core/perf.bend, over the text Perf.take answers.
//
// Effects run on the event loop only, so the table needs no lock.
//
// BACKPLANE_TRACE=<file> also writes every span, value and log line as a
// Chrome trace event (open it in ui.perfetto.dev or chrome://tracing).
// BACKPLANE_LOG_FILE=<file> appends log lines there as well as to stderr.

#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#define PERF_CAP 1024
#define PERF_BUCKETS 33
#define PERF_NAME 64
#define PERF_RING 512

typedef struct {
  char name[PERF_NAME];
  uint32_t kind;  // 0 spans (us), 1 gauge, 2 values
  uint64_t n, sum, max, last, mark;
  uint64_t b[PERF_BUCKETS];
} PerfStat;

static __attribute__((unused)) PerfStat perf_tab[PERF_CAP];
static __attribute__((unused)) uint32_t perf_used = 0;
static __attribute__((unused)) uint64_t perf_t0 = 0;
static __attribute__((unused)) FILE* perf_trace = NULL;
static __attribute__((unused)) int perf_trace_tried = 0;
static __attribute__((unused)) uint64_t perf_trace_flushed = 0;
static __attribute__((unused)) uint64_t perf_trace_n = 0;
static __attribute__((unused)) FILE* perf_logf = NULL;
static __attribute__((unused)) int perf_logf_tried = 0;
static __attribute__((unused)) char* perf_ring[PERF_RING];
static __attribute__((unused)) uint32_t perf_ring_at = 0;

static __attribute__((unused)) uint64_t perf_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static __attribute__((unused)) uint64_t perf_now_us(void) {
  if (perf_t0 == 0) {
    perf_t0 = perf_ns();
  }
  return (perf_ns() - perf_t0) / 1000ull;
}

// the slot for name (made on first use); the last slot takes overflow
static __attribute__((unused)) PerfStat* perf_slot(const char* name, u64 len) {
  if (len >= PERF_NAME) {
    len = PERF_NAME - 1;
  }
  uint64_t h = 1469598103934665603ull;
  for (u64 i = 0; i < len; i += 1) {
    h = (h ^ (uint8_t)name[i]) * 1099511628211ull;
  }
  for (uint32_t k = 0; k < PERF_CAP; k += 1) {
    PerfStat* s = &perf_tab[(h + k) % PERF_CAP];
    if (s->name[0] == 0) {
      if (perf_used >= PERF_CAP - 1) {
        break;
      }
      memcpy(s->name, name, len);
      s->name[len] = 0;
      perf_used += 1;
      return s;
    }
    if (strncmp(s->name, name, len) == 0 && s->name[len] == 0) {
      return s;
    }
  }
  PerfStat* o = &perf_tab[0];
  for (uint32_t k = 0; k < PERF_CAP; k += 1) {
    if (strcmp(perf_tab[k].name, "perf.overflow") == 0) {
      return &perf_tab[k];
    }
    if (perf_tab[k].name[0] == 0) {
      o = &perf_tab[k];
    }
  }
  strcpy(o->name, "perf.overflow");
  perf_used += 1;
  return o;
}

static __attribute__((unused)) uint32_t perf_bucket(uint64_t v) {
  uint32_t i = 0;
  while (v > 0 && i < PERF_BUCKETS - 1) {
    v >>= 1;
    i += 1;
  }
  return i;
}

static __attribute__((unused)) void perf_put(PerfStat* s, uint64_t v) {
  s->n += 1;
  s->sum += v;
  s->last = v;
  if (v > s->max) {
    s->max = v;
  }
  s->b[perf_bucket(v)] += 1;
}

// Tracing
// -------
// Events go into a buffer and reach the file whole (at most every 200 ms,
// or when the buffer fills), so a process killed mid-run leaves a file
// that ends between events; the format allows the missing ].

#define PERF_TBUF (1 << 16)

static __attribute__((unused)) char perf_tbuf[PERF_TBUF];
static __attribute__((unused)) size_t perf_tlen = 0;

static __attribute__((unused)) void perf_trace_flush(void) {
  size_t at = 0;
  while (perf_trace != NULL && at < perf_tlen) {
    size_t n = fwrite(perf_tbuf + at, 1, perf_tlen - at, perf_trace);
    if (n == 0) {
      break;
    }
    at += n;
  }
  if (perf_trace != NULL) {
    fflush(perf_trace);
  }
  perf_tlen = 0;
}

static __attribute__((unused)) void perf_trace_close(void) {
  if (perf_trace != NULL) {
    perf_trace_flush();
    fputs("\n]\n", perf_trace);
    fclose(perf_trace);
    perf_trace = NULL;
  }
}

static __attribute__((unused)) FILE* perf_tracer(void) {
  if (!perf_trace_tried) {
    perf_trace_tried = 1;
    const char* p = getenv("BACKPLANE_TRACE");
    if (p != NULL && p[0] != 0) {
      perf_trace = fopen(p, "w");
      if (perf_trace != NULL) {
        setvbuf(perf_trace, NULL, _IONBF, 0);
        fputs("[\n", perf_trace);
        atexit(perf_trace_close);
      }
    }
  }
  return perf_trace;
}

// one timeline row per area (the name's first part): ui, hub, http, ...
static __attribute__((unused)) uint32_t perf_tid(const char* name) {
  uint32_t h = 7;
  for (const char* c = name; *c != 0 && *c != '.'; c += 1) {
    h = h * 31 + (uint8_t)*c;
  }
  return 1 + h % 997;
}

// s as a JSON string's contents, cut to fit n bytes
static __attribute__((unused)) size_t perf_json(char* out, size_t n, const char* s) {
  size_t k = 0;
  for (; *s != 0 && k + 7 < n; s += 1) {
    uint8_t c = (uint8_t)*s;
    if (c == '"' || c == '\\') {
      out[k++] = '\\';
      out[k++] = (char)c;
    } else if (c < 32) {
      k += (size_t)snprintf(out + k, n - k, "\\u%04x", c);
    } else {
      out[k++] = (char)c;
    }
  }
  out[k] = 0;
  return k;
}

// one event: fields go after "name"; the buffer is written out when full
// or 200 ms after the last write
static __attribute__((unused)) void perf_trace_put(const char* name, const char* fields, uint64_t now) {
  if (perf_tracer() == NULL) {
    return;
  }
  char ev[1024];
  char esc[640];
  perf_json(esc, sizeof esc, name);
  int k = snprintf(ev, sizeof ev, "%s{\"name\":\"%s\",%s}", perf_trace_n == 0 ? "" : ",\n", esc, fields);
  if (k <= 0 || k >= (int)sizeof ev) {
    return;
  }
  perf_trace_n += 1;
  if (perf_tlen + (size_t)k > PERF_TBUF) {
    perf_trace_flush();
  }
  memcpy(perf_tbuf + perf_tlen, ev, (size_t)k);
  perf_tlen += (size_t)k;
  if (now - perf_trace_flushed > 200000ull) {
    perf_trace_flushed = now;
    perf_trace_flush();
  }
}

static __attribute__((unused)) void perf_trace_span(const char* name, uint64_t now, uint64_t dur) {
  char f[160];
  snprintf(f, sizeof f, "\"ph\":\"X\",\"ts\":%llu,\"dur\":%llu,\"pid\":%d,\"tid\":%u",
    (unsigned long long)(now - dur), (unsigned long long)dur, (int)getpid(), perf_tid(name));
  perf_trace_put(name, f, now);
}

static __attribute__((unused)) void perf_trace_count(const char* name, uint64_t now, uint64_t v) {
  char f[160];
  snprintf(f, sizeof f, "\"ph\":\"C\",\"ts\":%llu,\"pid\":%d,\"args\":{\"v\":%llu}",
    (unsigned long long)now, (int)getpid(), (unsigned long long)v);
  perf_trace_put(name, f, now);
}

static __attribute__((unused)) void perf_trace_note(const char* line, uint64_t now) {
  char f[160];
  snprintf(f, sizeof f, "\"ph\":\"i\",\"s\":\"g\",\"ts\":%llu,\"pid\":%d", (unsigned long long)now, (int)getpid());
  perf_trace_put(line, f, now);
}

// Perf.us
// -------

#ifdef CID_PERF_US

// microseconds since the first reading, as a U32 (it wraps after 71
// minutes; a span is the wrapping difference, so it stays right)
Term perf_us_run(Env e, Term* f, IoWork* w) {
  return (Term)(uint32_t)perf_now_us();
}

static void __attribute__((constructor)) perf_us_use(void) {
  io_eff(CID_PERF_US, perf_us_run, 0);
}

#endif

// Perf.span: record now - t0 under name; answers now (the next span's t0)
// ----------

#ifdef CID_PERF_SPAN

Term perf_span_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  uint64_t now = perf_now_us();
  uint32_t dur = (uint32_t)now - (uint32_t)f[1];
  PerfStat* s = perf_slot(name, len);
  perf_put(s, dur);
  perf_trace_span(s->name, now, dur);
  free(name);
  return (Term)(uint32_t)now;
}

static void __attribute__((constructor)) perf_span_use(void) {
  io_eff(CID_PERF_SPAN, perf_span_run, 0);
}

#endif

// Perf.add: record a value (a count, a size) under name
// --------

#ifdef CID_PERF_ADD

Term perf_add_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  PerfStat* s = perf_slot(name, len);
  s->kind = 2;
  perf_put(s, (uint32_t)f[1]);
  perf_trace_count(s->name, perf_now_us(), (uint32_t)f[1]);
  free(name);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) perf_add_use(void) {
  io_eff(CID_PERF_ADD, perf_add_run, 0);
}

#endif

// Perf.set: a gauge (only its last value means anything)
// --------

#ifdef CID_PERF_SET

Term perf_set_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  PerfStat* s = perf_slot(name, len);
  if (s->last != (uint32_t)f[1] || s->n == 0) {
    perf_trace_count(s->name, perf_now_us(), (uint32_t)f[1]);
  }
  s->kind = 1;
  perf_put(s, (uint32_t)f[1]);
  free(name);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) perf_set_use(void) {
  io_eff(CID_PERF_SET, perf_set_run, 0);
}

#endif

// Perf.mark / Perf.done: a span that starts at the first mark since the
// last done (input to pixels: every event marks, the frame that shows it
// is done)
// ---------------------

#ifdef CID_PERF_MARK

Term perf_mark_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  PerfStat* s = perf_slot(name, len);
  if (s->mark == 0) {
    s->mark = perf_now_us() + 1;
  }
  free(name);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) perf_mark_use(void) {
  io_eff(CID_PERF_MARK, perf_mark_run, 0);
}

#endif

#ifdef CID_PERF_DONE

Term perf_done_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* name = io_cstr(e, f[0], &len);
  PerfStat* s = perf_slot(name, len);
  if (s->mark != 0) {
    uint64_t now = perf_now_us();
    uint64_t dur = now - (s->mark - 1);
    s->mark = 0;
    perf_put(s, dur > 0xffffffffull ? 0xffffffffull : dur);
    perf_trace_span(s->name, now, dur);
  }
  free(name);
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) perf_done_use(void) {
  io_eff(CID_PERF_DONE, perf_done_run, 0);
}

#endif

// Perf.take: every row as text, one per line:
//   name \t kind \t n \t sum \t max \t last \t b0,b1,...
// plus proc.rss_kb, proc.cpu_us and proc.up_us read now
// ---------

#ifdef CID_PERF_TAKE

static void perf_row(char** buf, size_t* len, size_t* cap, const PerfStat* s) {
  char line[PERF_NAME + 64 + PERF_BUCKETS * 21];
  int k = snprintf(line, sizeof line, "%s\t%u\t%llu\t%llu\t%llu\t%llu\t", s->name, s->kind,
    (unsigned long long)s->n, (unsigned long long)s->sum, (unsigned long long)s->max, (unsigned long long)s->last);
  int top = PERF_BUCKETS - 1;
  while (top > 0 && s->b[top] == 0) {
    top -= 1;
  }
  for (int i = 0; i <= top && k < (int)sizeof line - 24; i += 1) {
    k += snprintf(line + k, sizeof line - (size_t)k, i == 0 ? "%llu" : ",%llu", (unsigned long long)s->b[i]);
  }
  line[k++] = '\n';
  if (*len + (size_t)k > *cap) {
    *cap = (*cap + (size_t)k) * 2;
    *buf = (char*)io_mem(realloc(*buf, *cap));
  }
  memcpy(*buf + *len, line, (size_t)k);
  *len += (size_t)k;
}

static void perf_gauge(char** buf, size_t* len, size_t* cap, const char* name, uint64_t v) {
  PerfStat s;
  memset(&s, 0, sizeof s);
  strncpy(s.name, name, PERF_NAME - 1);
  s.kind = 1;
  perf_put(&s, v);
  perf_row(buf, len, cap, &s);
}

Term perf_take_run(Env e, Term* f, IoWork* w) {
  size_t cap = 1 << 14, len = 0;
  char* buf = (char*)io_mem(malloc(cap));
  for (uint32_t k = 0; k < PERF_CAP; k += 1) {
    if (perf_tab[k].name[0] != 0 && perf_tab[k].n > 0) {
      perf_row(&buf, &len, &cap, &perf_tab[k]);
    }
  }
  struct rusage ru;
  getrusage(RUSAGE_SELF, &ru);
  long rss = 0;
  FILE* m = fopen("/proc/self/statm", "r");
  if (m != NULL) {
    long pages = 0;
    if (fscanf(m, "%*ld %ld", &pages) == 1) {
      rss = pages * (sysconf(_SC_PAGESIZE) / 1024);
    }
    fclose(m);
  } else {
    rss = ru.ru_maxrss;
  }
  perf_gauge(&buf, &len, &cap, "proc.rss_kb", (uint64_t)rss);
  perf_gauge(&buf, &len, &cap, "proc.peak_kb", (uint64_t)ru.ru_maxrss);
  perf_gauge(&buf, &len, &cap, "proc.cpu_ms",
    ((uint64_t)ru.ru_utime.tv_sec + (uint64_t)ru.ru_stime.tv_sec) * 1000ull + ((uint64_t)ru.ru_utime.tv_usec + (uint64_t)ru.ru_stime.tv_usec) / 1000ull);
  perf_gauge(&buf, &len, &cap, "proc.up_ms", perf_now_us() / 1000ull);
  Term r = io_str(e, buf, len);
  free(buf);
  return r;
}

static void __attribute__((constructor)) perf_take_use(void) {
  io_eff(CID_PERF_TAKE, perf_take_run, 0);
}

#endif

// Perf.emit: one log line to stderr, BACKPLANE_LOG_FILE, the trace and
// the ring Perf.logs answers
// ---------

#ifdef CID_PERF_EMIT

Term perf_emit_run(Env e, Term* f, IoWork* w) {
  u64 len = 0;
  char* line = io_cstr(e, f[0], &len);
  fwrite(line, 1, len, stderr);
  fputc('\n', stderr);
  if (!perf_logf_tried) {
    perf_logf_tried = 1;
    const char* p = getenv("BACKPLANE_LOG_FILE");
    if (p != NULL && p[0] != 0) {
      perf_logf = fopen(p, "a");
    }
  }
  if (perf_logf != NULL) {
    fwrite(line, 1, len, perf_logf);
    fputc('\n', perf_logf);
    fflush(perf_logf);
  }
  perf_trace_note(line, perf_now_us());
  free(perf_ring[perf_ring_at]);
  perf_ring[perf_ring_at] = line;
  perf_ring_at = (perf_ring_at + 1) % PERF_RING;
  return term_pak(CID_UNIT, 0);
}

static void __attribute__((constructor)) perf_emit_use(void) {
  io_eff(CID_PERF_EMIT, perf_emit_run, 0);
}

#endif

// Perf.logs: the last lines emitted, oldest first
// ---------

#ifdef CID_PERF_LOGS

Term perf_logs_run(Env e, Term* f, IoWork* w) {
  size_t len = 0;
  for (uint32_t k = 0; k < PERF_RING; k += 1) {
    if (perf_ring[k] != NULL) {
      len += strlen(perf_ring[k]) + 1;
    }
  }
  char* buf = (char*)io_mem(malloc(len + 1));
  size_t at = 0;
  for (uint32_t k = 0; k < PERF_RING; k += 1) {
    char* l = perf_ring[(perf_ring_at + k) % PERF_RING];
    if (l != NULL) {
      size_t n = strlen(l);
      memcpy(buf + at, l, n);
      buf[at + n] = '\n';
      at += n + 1;
    }
  }
  Term r = io_str(e, buf, at);
  free(buf);
  return r;
}

static void __attribute__((constructor)) perf_logs_use(void) {
  io_eff(CID_PERF_LOGS, perf_logs_run, 0);
}

#endif
