# Custom license overrides + in-repo maintainers not yet in nixpkgs.
_scope:
{ inputs, ... }:
inputs."nixpkgs".lib.extend (
  _final: prev: {
    licenses = prev.licenses // {
      # nixpkgs' unfree license but `free = true`, so these packages evaluate
      # without allowUnfree. Still labelled unfree in metadata and docs.
      unfree = prev.licenses.unfree // {
        free = true;
      };
      fsl11Mit = prev.licenses.fsl11Mit // {
        free = true;
      };
    };

    maintainers = prev.maintainers // {
      ak2k = {
        github = "ak2k";
        githubId = 19240940;
        name = "Adam";
      };
      Bad3r = {
        github = "Bad3r";
        githubId = 25513724;
        name = "Bad3r";
      };
      chernistry = {
        github = "chernistry";
        githubId = 73943355;
        name = "chernistry";
      };
      dancodes = {
        github = "dan-online";
        githubId = 41877062;
        name = "DanCodes";
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
      xbpk3t = {
        github = "xbpk3t";
        githubId = 8591495;
        name = "xbpk3t";
      };
      xorilog = {
        github = "xorilog";
        githubId = 5818406;
        name = "Christophe Boucharlat";
      };
      commandodev = {
        github = "commandodev";
        githubId = 87764;
        name = "Ben Ford";
      };
      odysseus0 = {
        github = "odysseus0";
        githubId = 8635094;
        name = "George Zhang";
      };
      yutakobayashidev = {
        github = "yutakobayashidev";
        githubId = 91340399;
        name = "Yuta Kobayashi";
      };
      zrubing = {
        github = "zrubing";
        githubId = 21324081;
        name = "Rubing";
      };
      titaniumtown = {
        github = "titaniumtown";
        githubId = 11786225;
        name = "Simon Gardling";
      };
      aliez-ren = {
        github = "aliez-ren";
        githubId = 8287771;
        name = "Aliez Ren";
      };
      SecBear = {
        github = "SecBear";
        githubId = 253731654;
        name = "Bryce Thorpe";
      };
      PieterPel = {
        github = "PieterPel";
        githubId = 25645555;
        name = "Pieter Pel";
      };
      smdex = {
        github = "smdex";
        githubId = 105790745;
        name = "Sergii Maksymov";
      };
      kusold = {
        github = "kusold";
        githubId = 509966;
        name = "Mike Kusold";
      };
      uesyn = {
        github = "uesyn";
        githubId = 17411645;
        name = "Shinya Uemura";
      };
      murlakatam = {
        github = "murlakatam";
        githubId = 38276;
        name = "Eugene Baranovsky";
      };
      viniciuspalma = {
        github = "viniciuspalma";
        githubId = 3676032;
        name = "Vinícius Palma";
      };
      pikdum = {
        github = "pikdum";
        githubId = 5122800;
        name = "pikdum";
      };
      benvinegar = {
        github = "benvinegar";
        githubId = 2153;
        name = "Ben Vinegar";
      };
      arch-fan = {
        github = "arch-fan";
        githubId = 55891793;
        name = "arch-fan";
      };
      fraggerfox = {
        github = "fraggerfox";
        githubId = 189939;
        name = "Santhosh Raju";
      };
      csanthiago = {
        github = "csanthiago";
        githubId = 8346803;
        name = "Cirios Santhiago";
      };
      scotttrinh = {
        github = "scotttrinh";
        githubId = 1682194;
        name = "Scott Trinh";
      };
      hobr = {
        github = "hobr";
        githubId = 13460388;
        name = "Hobr";
      };
      mnixry = {
        github = "mnixry";
        githubId = 32300164;
        name = "Mix";
      };
      iainlane = {
        github = "iainlane";
        githubId = 321014;
        name = "Iain Lane";
      };
      kmjayadeep = {
        github = "kmjayadeep";
        githubId = 6793260;
        name = "Jayadeep KM";
      };
      ahacop = {
        github = "ahacop";
        githubId = 1678968;
        name = "Ara Hacopian";
      };
      poelzi = {
        github = "poelzi";
        githubId = 66107;
        name = "Daniel Poelzleithner";
      };
      selmison = {
        github = "selmison";
        githubId = 24687232;
        name = "Selmison Miranda";
      };
      RyougiShiki-214 = {
        github = "RyougiShiki-214";
        githubId = 53418317;
        name = "Shiki";
      };
      jvmncs = {
        github = "jvmncs";
        githubId = 7891333;
        name = "Jason Mancuso";
      };
      JachinShen = {
        github = "JachinShen";
        githubId = 20773762;
        name = "JachinShen";
      };
      whazor = {
        github = "whazor";
        githubId = 184182;
        name = "Nanne";
      };
    };
  }
)
