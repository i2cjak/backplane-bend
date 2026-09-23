// Pseudo-terminals are native-only: the JS target answers ENOSYS.
function pty_spawn(cmd, args, cwd, cols, rows) {
  return io_fail(38);
}

function pty_resize(socket, cols, rows) {
  return socket;
}
