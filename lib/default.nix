{ inputs, ... }:
inputs.nixpkgs.lib.extend (
  _final: prev: {
    maintainers = prev.maintainers // {
      Bad3r = {
        github = "Bad3r";
        githubId = 25513724;
        name = "Bad3r";
      };
      ypares = {
        github = "YPares";
        githubId = 1377233;
        name = "Yves Parès";
      };
      Chickensoupwithrice = {
        github = "Chickensoupwithrice";
        githubId = 22575913;
        name = "Anish Lakhwara";
      };
      mulatta = {
        github = "mulatta";
        githubId = 67085791;
        name = "Seungwon Lee";
      };
      garbas = {
        github = "garbas";
        githubId = 20208;
        name = "Rok Garbas";
      };
      afterthought = {
        github = "afterthought";
        githubId = 198010;
        name = "Charles Swanberg";
      };
      xorilog = {
        github = "xorilog";
        githubId = 5818406;
        name = "Christophe Boucharlat";
      };
    };
  }
)
