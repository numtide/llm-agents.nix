{
  pkgs,
  flake,
  system,
}:

let
  chatgpt = flake.packages.${system}.chatgpt or null;
  chatgptWithPrimaryRuntime =
    if chatgpt != null then
      chatgpt.override {
        withPrimaryRuntime = true;
      }
    else
      null;
in
assert
  chatgpt == null
  || (
    !chatgpt.withPrimaryRuntime
    && chatgpt.primaryRuntime == null
    && chatgpt.runtimePython == null
    && (
      system != "x86_64-linux"
      || (
        chatgptWithPrimaryRuntime.withPrimaryRuntime
        && chatgptWithPrimaryRuntime.primaryRuntime != null
        && chatgptWithPrimaryRuntime.runtimePython != null
        && chatgptWithPrimaryRuntime.drvPath != chatgpt.drvPath
      )
    )
  );
pkgs.runCommand "chatgpt-packaging-check" { } ''
  touch $out
''
