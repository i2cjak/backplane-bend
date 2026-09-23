// Backplane host effects: the JS twin of host.c.
//
// The server ships as a native binary; this twin exists so `bend server.bend`
// runs for quick checks. Process effects answer ENOSYS here.

function host_libc() {
  if (globalThis.BACKPLANE_LIBC === undefined) {
    const ffi = require("bun:ffi");
    const mac = process.platform === "darwin";
    globalThis.BACKPLANE_LIBC = ffi.dlopen(mac ? "libSystem.dylib" : "libc.so.6", {
      dup: { args: ["i32"], returns: "i32" },
      shutdown: { args: ["i32", "i32"], returns: "i32" },
    }).symbols;
  }
  return globalThis.BACKPLANE_LIBC;
}

function host_errno(e) {
  return Math.abs(e?.errno ?? 5);
}

function clock_epoch() {
  return Math.floor(Date.now() / 1000) >>> 0;
}

function host_list(xs) {
  let out = { $: "Nil" };
  for (let i = xs.length; i > 0; i -= 1) {
    out = { $: "Con", head: xs[i - 1], tail: out };
  }
  return out;
}

function sock_recv_bytes(socket, max, k) {
  const sys = io_sys();
  const b = new Uint8Array(Math.max(Number(max), 1));
  const again = sys.mac ? 35 : 11;
  const go = () => {
    const n = Number(sys.recv(socket, sys.ptr(b), b.length, 0));
    if (n < 0) {
      const code = sys.errno();
      if (code === again) {
        io_park_on(socket, false, k, go);
        return undefined;
      }
      return io_tup(socket, io_fail(code));
    }
    return io_tup(socket, io_done(host_list(Array.from(b.subarray(0, n)))));
  };
  return go();
}

function sock_recv_bytes_need() {
  return { read: true };
}

function host_send(socket, b) {
  const sys = io_sys();
  let at = 0;
  while (at < b.length) {
    const n = Number(sys.send(socket, sys.ptr(b.subarray(at)), BigInt(b.length - at), 0x4000));
    if (n < 0) {
      const code = sys.errno();
      if (code === (sys.mac ? 35 : 11)) {
        continue;
      }
      return io_tup(socket, io_fail(code));
    }
    at += n;
  }
  return io_tup(socket, io_done({ $: "Unit" }));
}

function sock_send_bytes(socket, data) {
  const bytes = [];
  for (let xs = data; xs.$ === "Con"; xs = xs.tail) {
    bytes.push(xs.head);
  }
  if (bytes.some((x) => x > 255)) {
    return io_tup(socket, io_fail(22));
  }
  return host_send(socket, Uint8Array.from(bytes));
}

function sock_send_text(socket, text) {
  return host_send(socket, io_bytes(text));
}

function sock_dup(socket) {
  const got = host_libc().dup(socket);
  return io_tup(socket, got < 0 ? io_fail(io_sys().errno()) : io_done(got));
}

function sock_shutdown(socket) {
  host_libc().shutdown(socket, 1);
  return socket;
}

function proc_spawn(cmd, args, cwd, err) {
  return io_fail(38);
}

function proc_wait(pid) {
  return 255;
}

function proc_kill(pid, sig) {
  try {
    process.kill(pid, sig);
  } catch (e) {
  }
  return { $: "Unit" };
}

function fs_stat(path) {
  try {
    const st = require("fs").statSync(path);
    const kind = st.isFile() ? 0 : st.isDirectory() ? 1 : 2;
    return io_done(io_tup(kind, io_tup(Math.min(st.size, 0xffffffff) >>> 0,
      Math.floor(st.mtimeMs / 1000) >>> 0)));
  } catch (e) {
    return io_fail(host_errno(e));
  }
}

function fs_list(path) {
  try {
    return io_done(host_list(require("fs").readdirSync(path)));
  } catch (e) {
    return io_fail(host_errno(e));
  }
}

function fs_mkdirs(path) {
  try {
    require("fs").mkdirSync(path, { recursive: true });
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(host_errno(e));
  }
}

function fs_rename(from, to) {
  try {
    require("fs").renameSync(from, to);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(host_errno(e));
  }
}

function fs_remove(path) {
  try {
    require("fs").rmSync(path);
    return io_done({ $: "Unit" });
  } catch (e) {
    try {
      require("fs").rmdirSync(path);
      return io_done({ $: "Unit" });
    } catch (e2) {
      return io_fail(host_errno(e2));
    }
  }
}

function fs_chmod(path, mode) {
  try {
    require("fs").chmodSync(path, mode);
    return io_done({ $: "Unit" });
  } catch (e) {
    return io_fail(host_errno(e));
  }
}

function net_listen(host, port) {
  return io_fail(38);
}

function sys_exe_dir() {
  return require("path").dirname(process.argv[1] ?? "");
}
