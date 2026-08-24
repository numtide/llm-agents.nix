{ fetchFromGitHub }:

let
  version = "0.40.0";
in
{
  inherit version;

  src = fetchFromGitHub {
    owner = "lambda-symbolics";
    repo = "autolith";
    tag = "v${version}";
    hash = "sha256-apPIPXqXoTI5lH/nz9vZvdzYX9vBL3qk2tDe2LZg9+4=";
  };
}
