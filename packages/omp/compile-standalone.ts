// Compile the omp standalone binary via upstream's compileCodingAgent helper:
// the binary needs the `omp-legacy-pi-modules` virtual module, whose Bun.build()
// plugin `bun build --compile` cannot load.
//
// Usage (from packages/coding-agent, so bare package imports resolve like
// upstream's build-binary.ts): bun compile-standalone.ts

import { createRequire } from "node:module";
import * as path from "node:path";

const codingAgentDir = process.cwd();
const repoRoot = path.resolve(codingAgentDir, "..", "..");

const { compileCodingAgent } = await import(
	path.join(codingAgentDir, "scripts", "compile-binary.ts")
);

// Embed the Transformers.js version so the tiny-model worker can pin its install.
const require = createRequire(path.join(codingAgentDir, "package.json"));
const transformersManifest = require("@huggingface/transformers/package.json") as {
	version: string;
};

await compileCodingAgent({
	repoRoot,
	entrypoint: path.join(codingAgentDir, "src", "cli.ts"),
	outfile: path.join(repoRoot, "dist", "omp"),
	transformersVersion: transformersManifest.version,
});
