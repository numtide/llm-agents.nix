{
  lib,
  flake,
  symlinkJoin,
  t3code,
}:

symlinkJoin {
  name = "t3code-desktop";
  paths = [ t3code.desktop ];

  passthru.category = "AI Coding Agents";
  # Follows t3code, which the updater bumps.
  passthru.skipUpdate = true;

  meta = {
    description = "Desktop control surface for coding agents";
    homepage = "https://t3.codes";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${t3code.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ dancodes ];
    mainProgram = "t3code-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
