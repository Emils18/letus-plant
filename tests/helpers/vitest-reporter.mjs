export default async function* vitestReporter(source) {
  const start = performance.now();
  let passed = 0;
  let failed = 0;
  const files = new Set();

  for await (const event of source) {
    if (event.type === "test:pass") {
      passed++;
      const file = event.data.file ? event.data.file.replace(/\\/g, "/") : "";
      const rel = file.includes("/tests/") ? `tests/${file.split("/tests/")[1]}` : file;
      if (rel) files.add(rel);
      const ms = Math.round(event.data.details?.duration_ms ?? 1);
      yield `\x1b[32m✓\x1b[0m ${rel ? `${rel} > ` : ""}${event.data.name} \x1b[2m${ms}ms\x1b[0m\n`;
    } else if (event.type === "test:fail") {
      failed++;
      const file = event.data.file ? event.data.file.replace(/\\/g, "/") : "";
      const rel = file.includes("/tests/") ? `tests/${file.split("/tests/")[1]}` : file;
      if (rel) files.add(rel);
      yield `\x1b[31m×\x1b[0m ${rel ? `${rel} > ` : ""}${event.data.name}\n`;
    }
  }

  const totalFiles = Math.max(files.size, 1);
  const totalTests = passed + failed;
  const durationMs = Math.round(performance.now() - start);

  yield `\n`;
  if (failed === 0) {
    yield ` \x1b[2mTest Files\x1b[0m  \x1b[32m${totalFiles} passed\x1b[0m \x1b[2m(${totalFiles})\x1b[0m\n`;
    yield `      \x1b[2mTests\x1b[0m  \x1b[32m${passed} passed\x1b[0m \x1b[2m(${totalTests})\x1b[0m\n`;
  } else {
    yield ` \x1b[2mTest Files\x1b[0m  \x1b[31m${failed} failed\x1b[0m \x1b[2m(${totalFiles})\x1b[0m\n`;
    yield `      \x1b[2mTests\x1b[0m  \x1b[31m${failed} failed\x1b[0m | \x1b[32m${passed} passed\x1b[0m \x1b[2m(${totalTests})\x1b[0m\n`;
  }
  yield `   \x1b[2mDuration\x1b[0m  ${durationMs}ms\n`;
}
