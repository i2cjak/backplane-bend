// The native window has no JS twin: the app ships as a native binary.
function win_open(title, w, h) {
  return io_fail(38);
}
function win_words(win) {
  return io_tup(win, { $: "Nil" });
}
function win_present(win, image) {
  return io_tup(win, image);
}
function win_copy(win, text) {
  return win;
}
function win_paste(win) {
  return win;
}
function win_size(win) {
  return io_tup(win, io_tup(0, 0));
}
function win_twin(win) {
  return io_tup(win, win);
}
function win_title(win, title) {
  return win;
}
function win_pasted(win) {
  return io_tup(win, "");
}
function win_dropped(win) {
  return io_tup(win, "");
}
