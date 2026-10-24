const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const [appDir, version] = process.argv.slice(2);
assert.ok(process.versions.electron, "Native addons must load with the packaged Electron");

const metadata = JSON.parse(fs.readFileSync(path.join(appDir, "resources/app.asar/package.json"), "utf8"));
assert.equal(metadata.version, version.split(".").slice(0, 3).join("."));

const modules = path.join(appDir, "resources/app.asar.unpacked/node_modules");
const Database = require(path.join(appDir, "resources/app.asar/node_modules/better-sqlite3"));
const db = new Database(":memory:");
assert.equal(db.prepare("SELECT 1 AS result").get().result, 1);
db.close();
const pty = require(path.join(modules, `@lydell/node-pty-linux-${process.arch}/prebuilds/linux-${process.arch}/pty.node`));
assert.equal(typeof pty.fork, "function");
const koffi = require(path.join(appDir, "resources/app.asar/node_modules/koffi"));
const gl = koffi.load("libGL.so.1");
assert.equal(typeof gl.func("glGetString", "str", ["uint"]), "function");
console.log(`WorkBuddy ${version}: Electron and native modules load successfully`);
