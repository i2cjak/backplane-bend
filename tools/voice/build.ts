// Compile the helper into one executable (scripts/build-voice.sh).
const outfile = process.argv[2];
if (!outfile) throw new Error("usage: bun build.ts OUTFILE");

const result = await Bun.build({
  entrypoints: [`${import.meta.dir}/src/main.ts`],
  compile: { outfile },
  minify: true,
});
if (!result.success) {
  for (const log of result.logs) console.error(log);
  process.exit(1);
}
