// System fonts are native-only: the JS target keeps the bitmap font.
function font_find(pattern) {
  return io_fail(38);
}
function font_open(path, index, px) {
  return io_fail(38);
}
function font_metrics(face) {
  return { $: "Nil" };
}
function font_glyph(face, cp) {
  return { $: "Nil" };
}
function font_kern(face, a, b) {
  return 32768;
}
