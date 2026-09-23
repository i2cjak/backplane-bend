// Backplane host effects
// ======================
//
// The few things Base's effects do not cover: byte-exact sockets, child
// processes over a socketpair (so TCP.recv/TCP.send/TCP.poll serve their
// stdio), a wall clock, and filesystem metadata. Each block is compiled
// only when its def is used (#ifdef CID_...), as Base's own effects do.

#include <dirent.h>
#include <signal.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>

extern char** environ;

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

// A peer that hangs up must not kill the server.
static void __attribute__((constructor)) host_sigpipe(void) {
  signal(SIGPIPE, SIG_IGN);
}

static __attribute__((unused)) Term host_unit(void) {
  return term_pak(CID_UNIT, 0);
}

static __attribute__((unused)) Term host_bytes(Env e, const uint8_t* p, u64 n) {
  Term xs = term_pak(CID_NIL, 0);
  for (u64 i = n; i > 0; i -= 1) {
    xs = io_node(e, CID_CON, (Term)p[i - 1], xs);
  }
  return xs;
}

// Sends what is left of w->data; a full socket parks until writable.
static __attribute__((unused)) Term host_send_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  while (w->code == 0 && (u64)w->made < w->size) {
    ssize_t n = send(fd, w->data + w->made, w->size - (u64)w->made, MSG_NOSIGNAL);
    if (n < 0 && errno == EAGAIN) {
      return io_wait_on(w, fd, POLLOUT, 0, host_send_more);
    }
    w->made += io_sys_end(w, n);
  }
  Term r = w->code != 0 ? io_fail(e, w->code, NULL) : io_done(e, host_unit());
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

// Clock
// =====

#ifdef CID_CLOCK_EPOCH

Term clock_epoch_run(Env e, Term* f, IoWork* w) {
  return (Term)(uint32_t)time(NULL);
}

static void __attribute__((constructor)) clock_epoch_use(void) {
  io_eff(CID_CLOCK_EPOCH, clock_epoch_run, 0);
}

#endif

// Sock
// ====

#ifdef CID_SOCK_RECV_BYTES

static Term sock_recv_bytes_more(Env e, IoWork* w) {
  int fd  = (int)w->hand;
  w->size = io_sys_end(w, recv(fd, w->data, (size_t)w->made, 0));
  if (w->code == EAGAIN) {
    return io_wait_on(w, fd, POLLIN, 0, sock_recv_bytes_more);
  }
  Term r = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, host_bytes(e, (uint8_t*)w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

// Up to max bytes as they are; [] means the peer closed its side.
Term sock_recv_bytes_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->made = f[1] < INT32_MAX ? (intptr_t)f[1] : INT32_MAX;
  w->made = w->made > 0 ? w->made : 1;
  w->data = io_mem(malloc((size_t)w->made));
  return sock_recv_bytes_more(e, w);
}

static void __attribute__((constructor)) sock_recv_bytes_use(void) {
  io_eff(CID_SOCK_RECV_BYTES, sock_recv_bytes_run, IO_READ);
}

#endif

#ifdef CID_SOCK_SEND_BYTES

Term sock_send_bytes_run(Env e, Term* f, IoWork* w) {
  u64  cap = 256;
  Term xs  = f[1];
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->code = 0;
  w->size = 0;
  w->made = 0;
  w->data = io_mem(malloc(cap));
  while (term_aux(xs) == CID_CON) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, fb));
    if (w->size == cap) {
      cap *= 2;
      w->data = io_mem(realloc(w->data, cap));
    }
    w->code = fb[0] > 255 ? EINVAL : w->code;
    w->data[w->size++] = (char)fb[0];
    xs = fb[1];
  }
  if (w->code) {
    free(w->data);
    return io_tup(e, io_hand(w->hand), io_fail(e, w->code, NULL));
  }
  return host_send_more(e, w);
}

static void __attribute__((constructor)) sock_send_bytes_use(void) {
  io_eff(CID_SOCK_SEND_BYTES, sock_send_bytes_run, 0);
}

#endif

#ifdef CID_SOCK_SEND_TEXT

// A String sent as UTF-8, never raising SIGPIPE.
Term sock_send_text_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = io_cstr(e, f[1], &w->size);
  w->made = 0;
  w->code = 0;
  return host_send_more(e, w);
}

static void __attribute__((constructor)) sock_send_text_use(void) {
  io_eff(CID_SOCK_SEND_TEXT, sock_send_text_run, 0);
}

#endif

#ifdef CID_SOCK_DUP

// A second handle on the same socket, so one computation reads while
// another writes. Each handle is closed on its own.
Term sock_dup_run(Env e, Term* f, IoWork* w) {
  int fd  = (int)io_hand_v(f[0]);
  int got = dup(fd);
  if (got >= 0) {
    fcntl(got, F_SETFD, FD_CLOEXEC);
  }
  Term r = got < 0 ? io_fail(e, errno, NULL) : io_done(e, io_hand(got));
  return io_tup(e, io_hand(fd), r);
}

static void __attribute__((constructor)) sock_dup_use(void) {
  io_eff(CID_SOCK_DUP, sock_dup_run, 0);
}

#endif

#ifdef CID_SOCK_SHUTDOWN

// Ends our writing side (the peer reads EOF); reading continues.
Term sock_shutdown_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  shutdown(fd, SHUT_WR);
  return io_hand(fd);
}

static void __attribute__((constructor)) sock_shutdown_use(void) {
  io_eff(CID_SOCK_SHUTDOWN, sock_shutdown_run, 0);
}

#endif

// Proc
// ====

#if defined(CID_PROC_SPAWN) || defined(CID_SYS_EXEC)

static char** host_argv(Env e, Term cmd, Term xs, int* ok) {
  u64 cap = 8, n = 0, len = 0;
  char** v = (char**)io_mem(malloc(cap * sizeof(char*)));
  v[n++] = io_cstr(e, cmd, &len);
  *ok = !io_nul(v[0], len);
  while (term_aux(xs) == CID_CON) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, fb));
    if (n + 1 >= cap) {
      cap *= 2;
      v = (char**)io_mem(realloc(v, cap * sizeof(char*)));
    }
    v[n] = io_cstr(e, fb[0], &len);
    *ok = *ok && !io_nul(v[n], len);
    n += 1;
    xs = fb[1];
  }
  v[n] = NULL;
  return v;
}

#endif

#ifdef CID_PROC_SPAWN

// Starts cmd (searched on PATH) in cwd. Its stdin and stdout are one end of
// a socketpair; we keep the other, non-blocking. stderr: 0 discards it, 1
// joins it to stdout, 2 inherits ours. Answers (pid, socket).
Term proc_spawn_run(Env e, Term* f, IoWork* w) {
  int   ok   = 1;
  u64   clen = 0;
  char** argv = host_argv(e, f[0], f[1], &ok);
  char* cwd  = io_cstr(e, f[2], &clen);
  u32   err  = (u32)f[3];
  int   sv[2] = { -1, -1 };
  int   code = 0;
  pid_t pid  = 0;
  if (!ok || io_nul(cwd, clen)) {
    code = EILSEQ;
  } else if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
    code = errno;
  } else {
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    if (clen > 0) {
      posix_spawn_file_actions_addchdir_np(&fa, cwd);
    }
    posix_spawn_file_actions_adddup2(&fa, sv[1], 0);
    posix_spawn_file_actions_adddup2(&fa, sv[1], 1);
    if (err == 0) {
      posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    } else if (err == 1) {
      posix_spawn_file_actions_adddup2(&fa, sv[1], 2);
    }
    posix_spawn_file_actions_addclose(&fa, sv[0]);
    posix_spawnattr_t at;
    posix_spawnattr_init(&at);
    sigset_t def;
    sigemptyset(&def);
    sigaddset(&def, SIGPIPE);
    posix_spawnattr_setsigdefault(&at, &def);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGDEF);
    code = posix_spawnp(&pid, argv[0], &fa, &at, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&at);
    close(sv[1]);
    if (code != 0) {
      close(sv[0]);
    } else {
      fcntl(sv[0], F_SETFL, fcntl(sv[0], F_GETFL) | O_NONBLOCK);
      fcntl(sv[0], F_SETFD, FD_CLOEXEC);
    }
  }
  for (char** a = argv; *a != NULL; a += 1) {
    free(*a);
  }
  free(argv);
  free(cwd);
  if (code != 0) {
    return io_fail(e, code, NULL);
  }
  return io_done(e, io_tup(e, (Term)(uint32_t)pid, io_hand(sv[0])));
}

static void __attribute__((constructor)) proc_spawn_use(void) {
  io_eff(CID_PROC_SPAWN, proc_spawn_run, 0);
}

#endif

#ifdef CID_PROC_WAIT

static void proc_wait_call(IoWork* w) {
  int st = 0;
  pid_t r;
  do {
    r = waitpid((pid_t)w->word, &st, 0);
  } while (r < 0 && errno == EINTR);
  w->made = r < 0 ? 255 : WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
}

static Term proc_wait_pack(Env e, IoWork* w) {
  return (Term)(uint32_t)w->made;
}

// The exit code (128 + signal when killed), once the child ends.
Term proc_wait_run(Env e, Term* f, IoWork* w) {
  w->word = (uint32_t)f[0];
  return io_work(w, proc_wait_call, proc_wait_pack);
}

static void __attribute__((constructor)) proc_wait_use(void) {
  io_eff(CID_PROC_WAIT, proc_wait_run, 0);
}

#endif

#ifdef CID_PROC_KILL

Term proc_kill_run(Env e, Term* f, IoWork* w) {
  kill((pid_t)(uint32_t)f[0], (int)(uint32_t)f[1]);
  return host_unit();
}

static void __attribute__((constructor)) proc_kill_use(void) {
  io_eff(CID_PROC_KILL, proc_kill_run, 0);
}

#endif

// FS
// ==

#ifdef CID_FS_STAT

// (kind, (size, mtime)): kind 0 file, 1 directory, 2 other.
Term fs_stat_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* p = io_cstr(e, f[0], &n);
  struct stat st;
  int r = io_nul(p, n) ? -1 : stat(p, &st);
  int code = r < 0 ? (io_nul(p, n) ? EILSEQ : errno) : 0;
  free(p);
  if (code) {
    return io_fail(e, code, NULL);
  }
  u32 kind = S_ISREG(st.st_mode) ? 0 : S_ISDIR(st.st_mode) ? 1 : 2;
  u32 size = st.st_size > 0xFFFFFFFFll ? 0xFFFFFFFFu : (u32)st.st_size;
  return io_done(e, io_tup(e, (Term)kind,
    io_tup(e, (Term)size, (Term)(uint32_t)st.st_mtime)));
}

static void __attribute__((constructor)) fs_stat_use(void) {
  io_eff(CID_FS_STAT, fs_stat_run, 0);
}

#endif

#ifdef CID_FS_LIST

// The names in a directory, without "." and "..", in no set order.
Term fs_list_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* p = io_cstr(e, f[0], &n);
  DIR* d = io_nul(p, n) ? NULL : opendir(p);
  int code = d == NULL ? (io_nul(p, n) ? EILSEQ : errno) : 0;
  free(p);
  if (code) {
    return io_fail(e, code, NULL);
  }
  Term xs = term_pak(CID_NIL, 0);
  struct dirent* ent;
  while ((ent = readdir(d)) != NULL) {
    const char* s = ent->d_name;
    if (strcmp(s, ".") == 0 || strcmp(s, "..") == 0) {
      continue;
    }
    xs = io_node(e, CID_CON, io_str(e, s, strlen(s)), xs);
  }
  closedir(d);
  return io_done(e, xs);
}

static void __attribute__((constructor)) fs_list_use(void) {
  io_eff(CID_FS_LIST, fs_list_run, 0);
}

#endif

#ifdef CID_FS_MKDIRS

// mkdir -p
Term fs_mkdirs_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* p = io_cstr(e, f[0], &n);
  int code = io_nul(p, n) ? EILSEQ : 0;
  for (u64 i = 1; code == 0 && i <= n; i += 1) {
    if (i == n || p[i] == '/') {
      char c = p[i];
      p[i] = 0;
      if (mkdir(p, 0755) < 0 && errno != EEXIST) {
        code = errno;
      }
      p[i] = c;
    }
  }
  free(p);
  return code ? io_fail(e, code, NULL) : io_done(e, host_unit());
}

static void __attribute__((constructor)) fs_mkdirs_use(void) {
  io_eff(CID_FS_MKDIRS, fs_mkdirs_run, 0);
}

#endif

#ifdef CID_FS_RENAME

// Atomic within a filesystem: writers stage a file, then rename it over.
Term fs_rename_run(Env e, Term* f, IoWork* w) {
  u64 a = 0, b = 0;
  char* from = io_cstr(e, f[0], &a);
  char* to   = io_cstr(e, f[1], &b);
  int code = io_nul(from, a) || io_nul(to, b) ? EILSEQ
    : rename(from, to) < 0 ? errno : 0;
  free(from);
  free(to);
  return code ? io_fail(e, code, NULL) : io_done(e, host_unit());
}

static void __attribute__((constructor)) fs_rename_use(void) {
  io_eff(CID_FS_RENAME, fs_rename_run, 0);
}

#endif

#ifdef CID_FS_REMOVE

// Removes a file or an empty directory.
Term fs_remove_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* p = io_cstr(e, f[0], &n);
  int code = io_nul(p, n) ? EILSEQ : remove(p) < 0 ? errno : 0;
  free(p);
  return code ? io_fail(e, code, NULL) : io_done(e, host_unit());
}

static void __attribute__((constructor)) fs_remove_use(void) {
  io_eff(CID_FS_REMOVE, fs_remove_run, 0);
}

#endif

#ifdef CID_FS_CHMOD

Term fs_chmod_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* p = io_cstr(e, f[0], &n);
  int code = io_nul(p, n) ? EILSEQ : chmod(p, (mode_t)(uint32_t)f[1]) < 0 ? errno : 0;
  free(p);
  return code ? io_fail(e, code, NULL) : io_done(e, host_unit());
}

static void __attribute__((constructor)) fs_chmod_use(void) {
  io_eff(CID_FS_CHMOD, fs_chmod_run, 0);
}

#endif

// Net
// ===

#ifdef CID_NET_LISTEN

// TCP.listen binds every interface; the harness runs agents with shell
// access, so it listens on the host it is told (127.0.0.1 by default).
Term net_listen_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* host = io_cstr(e, f[0], &n);
  uint32_t port = (uint32_t)f[1];
  struct sockaddr_in at;
  int code = 0, fd = -1;
  if (io_nul(host, n) || io_sys_addr(host, port, &at) < 0) {
    code = EINVAL;
  } else if ((fd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
    code = errno;
  } else {
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (bind(fd, (struct sockaddr*)&at, sizeof(at)) < 0 || listen(fd, 64) < 0
      || fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0) {
      code = errno;
      close(fd);
    } else {
      fcntl(fd, F_SETFD, FD_CLOEXEC);
    }
  }
  free(host);
  return code ? io_fail(e, code, NULL) : io_done(e, io_hand(fd));
}

static void __attribute__((constructor)) net_listen_use(void) {
  io_eff(CID_NET_LISTEN, net_listen_run, 0);
}

#endif

// Sys
// ===

#if defined(CID_SYS_EXE_DIR) || defined(CID_SYS_EXE_PATH)

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

// the running binary's full path (n = its length; 0 when unknown)
static ssize_t host_exe(char* buf, size_t cap) {
  ssize_t n = -1;
#ifdef __APPLE__
  uint32_t size = (uint32_t)cap;
  char raw[4096];
  if (_NSGetExecutablePath(raw, &size) == 0 && realpath(raw, buf) != NULL) {
    n = (ssize_t)strlen(buf);
  }
#else
  n = readlink("/proc/self/exe", buf, cap - 1);
#endif
  if (n > 0) {
    buf[n] = 0;
  }
  return n;
}

#endif

#ifdef CID_SYS_EXE_PATH

Term sys_exe_path_run(Env e, Term* f, IoWork* w) {
  char buf[4096];
  ssize_t n = host_exe(buf, sizeof buf);
  return io_str(e, buf, n > 0 ? (u64)n : 0);
}

static void __attribute__((constructor)) sys_exe_path_use(void) {
  io_eff(CID_SYS_EXE_PATH, sys_exe_path_run, 0);
}

#endif

#ifdef CID_SYS_EXE_DIR

// The directory holding the running binary ("" when unknown).
Term sys_exe_dir_run(Env e, Term* f, IoWork* w) {
  char buf[4096];
  ssize_t n = host_exe(buf, sizeof buf);
  if (n <= 0) {
    return io_str(e, "", 0);
  }
  char* slash = strrchr(buf, '/');
  size_t len = slash == NULL ? 0 : (size_t)(slash - buf);
  return io_str(e, buf, len);
}

static void __attribute__((constructor)) sys_exe_dir_use(void) {
  io_eff(CID_SYS_EXE_DIR, sys_exe_dir_run, 0);
}

#endif

#ifdef CID_SYS_EXEC

// Replace this process with path (argv[0] = path, then args). Descriptors
// are close-on-exec, so agents see their stdin close and exit. Answers only
// on failure.
Term sys_exec_run(Env e, Term* f, IoWork* w) {
  int ok = 1;
  char** argv = host_argv(e, f[0], f[1], &ok);
  int code = ok ? 0 : EILSEQ;
  if (ok) {
    execv(argv[0], argv);
    code = errno;
  }
  for (char** a = argv; *a != NULL; a += 1) {
    free(*a);
  }
  free(argv);
  return io_fail(e, code, NULL);
}

static void __attribute__((constructor)) sys_exec_use(void) {
  io_eff(CID_SYS_EXEC, sys_exec_run, 0);
}

#endif
