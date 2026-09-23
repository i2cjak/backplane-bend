// Backplane pty effects
// =====================
//
// Pseudo-terminals for the integrated terminal. The master side is handed
// back as a Socket handle (a bare fd, non-blocking, close-on-exec), so
// host.c's Sock.recv_bytes / Sock.send_bytes read and write it (they fall
// back from recv/send to read/write on ENOTSOCK, and read EIO, the pty's
// hang-up, as end of stream) and Socket.close hangs it up.
//
// Linux and macOS: posix_openpt + grantpt + unlockpt + ptsname, then fork;
// the child makes a new session, takes the slave as its controlling
// terminal (TIOCSCTTY), and execs. The child only makes async-signal-safe
// calls (the runtime is multi-threaded), so PATH search and the environment
// are prepared before fork. Windows answers ENOSYS (ConPTY is not wired).

#if defined(CID_PTY_SPAWN) || defined(CID_PTY_RESIZE)

#if defined(_WIN32)

#ifdef CID_PTY_SPAWN
Term pty_spawn_run(Env e, Term* f, IoWork* w) {
  return io_fail(e, ENOSYS, NULL);
}

static void __attribute__((constructor)) pty_spawn_use(void) {
  io_eff(CID_PTY_SPAWN, pty_spawn_run, 0);
}
#endif

#ifdef CID_PTY_RESIZE
Term pty_resize_run(Env e, Term* f, IoWork* w) {
  return f[0];
}

static void __attribute__((constructor)) pty_resize_use(void) {
  io_eff(CID_PTY_RESIZE, pty_resize_run, 0);
}
#endif

#else

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

extern char** environ;

static void pty_size(int fd, u32 cols, u32 rows) {
  struct winsize ws;
  memset(&ws, 0, sizeof ws);
  ws.ws_col = (unsigned short)(cols > 0 && cols < 65536 ? cols : 80);
  ws.ws_row = (unsigned short)(rows > 0 && rows < 65536 ? rows : 24);
  ioctl(fd, TIOCSWINSZ, &ws);
}

#ifdef CID_PTY_SPAWN

// cmd then args as a NULL-ended argv; *ok is 0 when one holds a NUL
static char** pty_argv(Env e, Term cmd, Term xs, int* ok) {
  u64 cap = 8, n = 0, len = 0;
  char** v = (char**)io_mem(malloc(cap * sizeof(char*)));
  v[n++] = io_cstr(e, cmd, &len);
  *ok = !io_nul(v[0], len) && len > 0;
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

static void pty_free(char** v) {
  for (char** a = v; *a != NULL; a += 1) {
    free(*a);
  }
  free(v);
}

// the program to exec: cmd itself when it has a slash, else the first
// executable cmd on PATH (NULL when none)
static char* pty_which(const char* cmd) {
  if (strchr(cmd, '/') != NULL) {
    return strdup(cmd);
  }
  const char* path = getenv("PATH");
  if (path == NULL || *path == 0) {
    path = "/usr/local/bin:/usr/bin:/bin";
  }
  size_t clen = strlen(cmd);
  while (1) {
    const char* end = strchr(path, ':');
    size_t dlen = end == NULL ? strlen(path) : (size_t)(end - path);
    char* full = (char*)io_mem(malloc(dlen + clen + 3));
    if (dlen == 0) {
      memcpy(full, ".", 1);
      dlen = 1;
    } else {
      memcpy(full, path, dlen);
    }
    full[dlen] = '/';
    memcpy(full + dlen + 1, cmd, clen + 1);
    struct stat st;
    if (access(full, X_OK) == 0 && stat(full, &st) == 0 && S_ISREG(st.st_mode)) {
      return full;
    }
    free(full);
    if (end == NULL) {
      return NULL;
    }
    path = end + 1;
  }
}

// our environment with TERM=xterm-256color and COLORTERM=truecolor, and
// without LINES / COLUMNS (the pty's size is the truth)
static char** pty_env(void) {
  size_t n = 0;
  while (environ[n] != NULL) {
    n += 1;
  }
  char** v = (char**)io_mem(malloc((n + 3) * sizeof(char*)));
  size_t k = 0;
  for (size_t i = 0; i < n; i += 1) {
    const char* s = environ[i];
    if (strncmp(s, "TERM=", 5) == 0 || strncmp(s, "COLORTERM=", 10) == 0
      || strncmp(s, "LINES=", 6) == 0 || strncmp(s, "COLUMNS=", 8) == 0) {
      continue;
    }
    v[k++] = (char*)s;
  }
  v[k++] = (char*)"TERM=xterm-256color";
  v[k++] = (char*)"COLORTERM=truecolor";
  v[k] = NULL;
  return v;
}

// In the child, after fork: only async-signal-safe calls. On failure the
// errno goes up the report pipe and the child exits 127.
static void pty_child(int m, const char* slave, const char* cwd, const char* prog,
    char** argv, char** envp, int report, int maxfd) {
  int code = 0;
  sigset_t none;
  sigemptyset(&none);
  sigprocmask(SIG_SETMASK, &none, NULL);
  struct sigaction dfl;
  memset(&dfl, 0, sizeof dfl);
  dfl.sa_handler = SIG_DFL;
  int sigs[] = { SIGPIPE, SIGINT, SIGQUIT, SIGHUP, SIGTERM, SIGCHLD, SIGTSTP, SIGTTIN, SIGTTOU, SIGWINCH };
  for (size_t i = 0; i < sizeof sigs / sizeof sigs[0]; i += 1) {
    sigaction(sigs[i], &dfl, NULL);
  }
  close(m);
  if (setsid() < 0) {
    code = errno;
  }
  int s = code ? -1 : open(slave, O_RDWR);
  if (s < 0 && code == 0) {
    code = errno;
  }
#ifdef TIOCSCTTY
  if (code == 0 && ioctl(s, TIOCSCTTY, 0) < 0) {
    code = errno;
  }
#endif
  if (code == 0) {
    dup2(s, 0);
    dup2(s, 1);
    dup2(s, 2);
    // nothing else of ours leaks into the shell (listening sockets, files)
    int left = 1;
#if defined(__linux__) && defined(SYS_close_range)
    left = (report > 3 && syscall(SYS_close_range, 3u, (unsigned)report - 1, 0u) < 0)
      || syscall(SYS_close_range, (unsigned)report + 1, ~0u, 0u) < 0;
#endif
    for (int fd = 3; left && fd < maxfd; fd += 1) {
      if (fd != report) {
        close(fd);
      }
    }
    if (cwd[0] != 0 && chdir(cwd) < 0) {
      code = errno;
    }
  }
  if (code == 0) {
    execve(prog, argv, envp);
    code = errno;
  }
  ssize_t wr = write(report, &code, sizeof code);
  (void)wr;
  _exit(127);
}

// Answers (pid, master socket).
Term pty_spawn_run(Env e, Term* f, IoWork* w) {
  int    ok   = 1;
  u64    clen = 0;
  char** argv = pty_argv(e, f[0], f[1], &ok);
  char*  cwd  = io_cstr(e, f[2], &clen);
  u32    cols = (u32)f[3];
  u32    rows = (u32)f[4];
  char*  prog = NULL;
  char** envp = NULL;
  int    code = 0;
  int    m    = -1;
  int    rp[2] = { -1, -1 };
  pid_t  pid  = -1;
  char   slave[256];
  if (!ok || io_nul(cwd, clen)) {
    code = EILSEQ;
  } else if ((prog = pty_which(argv[0])) == NULL) {
    code = ENOENT;
  } else if ((m = posix_openpt(O_RDWR | O_NOCTTY)) < 0) {
    code = errno;
  } else if (grantpt(m) < 0 || unlockpt(m) < 0) {
    code = errno;
  } else {
#if defined(__linux__)
    if (ptsname_r(m, slave, sizeof slave) != 0) {
      code = errno ? errno : ENOTTY;
    }
#else
    // macOS / BSD: ptsname's buffer is static; we copy it at once
    const char* sn = ptsname(m);
    if (sn == NULL || strlen(sn) >= sizeof slave) {
      code = errno ? errno : ENOTTY;
    } else {
      strcpy(slave, sn);
    }
#endif
  }
  if (code == 0 && pipe(rp) < 0) {
    code = errno;
  }
  if (code == 0) {
    fcntl(rp[0], F_SETFD, FD_CLOEXEC);
    fcntl(rp[1], F_SETFD, FD_CLOEXEC);
    fcntl(m, F_SETFD, FD_CLOEXEC);
    pty_size(m, cols, rows);
    envp = pty_env();
    long lim = sysconf(_SC_OPEN_MAX);
    int maxfd = lim < 256 ? 256 : lim > 65536 ? 65536 : (int)lim;
    pid = fork();
    if (pid < 0) {
      code = errno;
    } else if (pid == 0) {
      pty_child(m, slave, cwd, prog, argv, envp, rp[1], maxfd);
    }
  }
  if (rp[1] >= 0) {
    close(rp[1]);
  }
  if (code == 0) {
    // the report pipe closes on exec (EOF, success) or carries errno
    int got = 0;
    ssize_t n;
    do {
      n = read(rp[0], &got, sizeof got);
    } while (n < 0 && errno == EINTR);
    if (n == (ssize_t)sizeof got) {
      code = got ? got : ECHILD;
      int st = 0;
      waitpid(pid, &st, 0);
    }
  }
  if (rp[0] >= 0) {
    close(rp[0]);
  }
  pty_free(argv);
  free(cwd);
  free(prog);
  free(envp);
  if (code != 0) {
    if (m >= 0) {
      close(m);
    }
    return io_fail(e, code, NULL);
  }
  fcntl(m, F_SETFL, fcntl(m, F_GETFL) | O_NONBLOCK);
  return io_done(e, io_tup(e, (Term)(uint32_t)pid, io_hand(m)));
}

static void __attribute__((constructor)) pty_spawn_use(void) {
  io_eff(CID_PTY_SPAWN, pty_spawn_run, 0);
}

#endif

#ifdef CID_PTY_RESIZE

Term pty_resize_run(Env e, Term* f, IoWork* w) {
  int fd = (int)io_hand_v(f[0]);
  pty_size(fd, (u32)f[1], (u32)f[2]);
  return io_hand(fd);
}

static void __attribute__((constructor)) pty_resize_use(void) {
  io_eff(CID_PTY_RESIZE, pty_resize_run, 0);
}

#endif

#endif

#endif
