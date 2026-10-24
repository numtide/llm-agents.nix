# WorkBuddy

WorkBuddy is Tencent's desktop AI assistant for working with local files and
automating tasks.

| Nix platform | Edition | Official download host |
| --- | --- | --- |
| `aarch64-darwin` | International ([workbuddy.ai](https://www.workbuddy.ai/)) | `download.codebuddy.ai` |
| `x86_64-linux`, `aarch64-linux` | Chinese ([workbuddy.cn](https://www.workbuddy.cn/)) | `download.codebuddy.cn` |

These are different editions with independent releases. The international Linux
feed currently points to unavailable downloads, so Linux deliberately uses the
official Chinese edition. The Linux update channels are documented by
[workbuddy-linux](https://github.com/ziyue67/workbuddy-linux); this package
downloads directly from Tencent, without running that project's installer.

Run the desktop application:

```sh
nix run github:numtide/llm-agents.nix#workbuddy
```

On Linux, the package includes desktop icons and a `workbuddy://` URI handler.
Install it in your NixOS or Home Manager configuration to make the launcher and
handler available to your desktop environment. It patches the bundled Electron,
Node, Python, and native modules for Nix. Other tools invoked by agents, such as
Git, are taken from your environment's `PATH`.

On macOS, the application is available as `Applications/WorkBuddy AI.app` and
registers `workbuddy-ai://` links. Its bundle is preserved without fixup.
Signature checks pin the main application executable
to Tencent's Developer ID; the archive is also pinned by its content hash.
Unsigned build intermediates and third-party signatures in the upstream bundle
prevent applying a blanket same-publisher check to every Mach-O file.

## Updates

```sh
./packages/workbuddy/update.py
```

The updater queries each platform's official channel, records its version and
URL, and downloads changed releases to calculate their hashes. It writes
`hashes.json` after all channels succeed and rejects downgrades. Unchanged
releases retain their hashes. To refresh archives republished at the same URL:

```sh
./packages/workbuddy/update.py --force
```

Update through Nix when a new package version becomes available. The application
cannot replace files in the Nix store through its own update mechanism.
