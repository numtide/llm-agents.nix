// Compile the omp standalone binary via upstream's compileCodingAgent helper:
// the binary needs the `omp-legacy-pi-modules` virtual module, whose Bun.build()
// plugin `bun build --compile` cannot load.
//
// Usage (from packages/coding-agent, so bare package imports resolve like
// upstream's build-binary.ts): bun compile-standalone.ts [target]

import * as path from "node:path";

const codingAgentDir = process.cwd();
const repoRoot = path.resolve(codingAgentDir, "..", "..");

const { compileCodingAgent } = await import(
	path.join(codingAgentDir, "scripts", "compile-binary.ts")
);

await compileCodingAgent({
	repoRoot,
	entrypoint: path.join(codingAgentDir, "src", "cli.ts"),
	outfile: path.join(repoRoot, "dist", "omp"),
	// The addon ships next to the binary; native.ts probes for it there.
	native: null,
	target: process.argv[2],
});
