args@{
  rev    ? "7a94fcdda304d143f9a40006c033d7e190311b54"
, sha256 ? "0d643wp3l77hv2pmg2fi7vyxn4rwy0iyr8djcw1h5x72315ck9ik"

, pkgs   ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
    inherit sha256; }) {
    config.allowUnfree = true;
    config.allowBroken = false;
  }
}:

let

pact-info = {
  branch = "master";
  rev = "4fc970ffc1a8fc41769920c88dc4818f4b5380cb";
  sha256 = "01rz4mn5p4q5wv40qajw5gsbbw7z5q1sfxc1fg9hvlv2iv7f8ahl";
};

pact-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "pact";
  # rev = "4fc970ffc1a8fc41769920c88dc4818f4b5380cb";
  # sha256 = "01rz4mn5p4q5wv40qajw5gsbbw7z5q1sfxc1fg9hvlv2iv7f8ahl";
  inherit (pact-info) rev sha256;
  # date = "2022-08-31T16:17:05-06:00";
};

# pact-src = ~/kadena/current/pact;

pact-drv = pkgs.stdenv.mkDerivation rec {
  name = "pact-drv-${version}";
  version = "4.4";

  src = pact-src;

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    cp ${./pact.nix} default.nix
  '';

  installPhase = ''
    mkdir -p $out
    cp -pR * $out
  '';
};

pact = pkgs.haskell.lib.compose.justStaticExecutables
  (import "${pact-drv}" {});

chainweb-node-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "chainweb-node";
  rev = "71eb31f431739fff962e24dae4b28a6fcdd5f543";
  sha256 = "1mi25pcdmgi70c2ahwkazkfjsfrxsjy1v7n38drknma9j1j2h05a";
  # date = "2022-08-29T10:41:38+02:00";
};

# chainweb-node-src = ~/kadena/chainweb-node;

chainweb-node-drv = pkgs.stdenv.mkDerivation rec {
  name = "chainweb-node-drv-${version}";
  version = "2.16";

  src = chainweb-node-src;

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    sed -i -e 's%"branch": ".*",%"branch": "${pact-info.branch}",%' dep/pact/github.json
    sed -i -e 's%"rev": ".*",%"rev": "${pact-info.rev}",%' dep/pact/github.json
    sed -i -e 's%"sha256": ".*"%"sha256": "${pact-info.sha256}"%' dep/pact/github.json
    cat dep/pact/github.json
  '';

  installPhase = ''
    mkdir -p $out
    cp -pR * $out
  '';
};

chainweb-node = pkgs.haskell.lib.compose.justStaticExecutables
  ((import "${chainweb-node-drv}" {}).overrideAttrs(_: {
      preBuild = ''
        sed -i -e 's/2_965_885/2_939_323/' src/Chainweb/Version.hs
      '';
    }));

chainweb-data-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "chainweb-data";
  rev = "5d815a70c544eead5964ba4e84d8f71fb8977300";
  sha256 = "111mczhhq7fqk784raa7zg1g9fd2gknph01265hyf4vzmxgr0y6r";
  # date = "2022-08-04T20:20:13-07:00";
};

chainweb-data = pkgs.haskell.lib.compose.justStaticExecutables
  ((import chainweb-data-src {}).overrideAttrs (_: {
     preConfigure = ''
       sed -i -e 's/ghc-options:    -threaded/-- ghc-options:    -threaded/' \
           chainweb-data.cabal
     '';
   }));

toYAML = name: data:
  pkgs.writeText name (pkgs.lib.generators.toYAML {} data);

configFile = toYAML "chainweb-node.config" {
  logging = {
    telemetryBackend = {
      enabled = true;
      configuration = {
        handle = "stdout";
        color = "auto";
        format = "text";
      };
    };

    backend = {
      handle = "stdout";
      color = "auto";
      format = "text";
    };

    logger = {
      log_level = "info";
      # log_level = "debug";
    };

    filter = {
      rules = [
        { key = "component";
          value = "cut-monitor";
          level = "info"; }
      ];
      default = "error";
      # default = "debug";
    };
  };

  chainweb = {
    allowReadsInLocal = true;
    headerStream = true;
    throttling = {
      global = 10000;
    };
  };
};

start-kadena = with pkgs; stdenv.mkDerivation rec {
  name = "start-kadena-${version}";
  version = "2.16";

  src = chainweb-data-src;

  buildInputs = [
    chainweb-node
    postgresql
    chainweb-data
    tmux
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin

    cat <<'EOF' > $out/bin/start-kadena
#!${bash}/bin/bash

NODE=$HOME/.local/share/chainweb-node
DATA=$HOME/.local/share/chainweb-data

if [[ ! -f "$DATA/pgdata/PG_VERSION" ]]; then
    mkdir -p $DATA/pgdata
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" initdb
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" \
        -l $DATA/chainweb-pgdata.log start
    sleep 5
    ${postgresql}/bin/createdb chainweb-data || echo "OK: db already exists"
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    echo "Postgres failed to start; see $DATA/chainweb-pgdata.log"
    exit 1
fi

cd $DATA

if [[ ! -f scripts/richlist.sh ]]; then
    mkdir -p scripts
    cp ${src}/scripts/richlist.sh scripts/richlist.sh
fi

if [[ ! -d $NODE/mainnet01 ]]; then
    mkdir -p $NODE
fi

exec ${tmux}/bin/tmux new-session \; \
  send-keys "\
    cd $NODE && \
    ${chainweb-node}/bin/chainweb-node \
      --config-file ${configFile} \
      --disable-node-mining \
      --bootstrap-reachability 0 \
      --p2p-port=1790 \
      2>&1 | tee chainweb-node.log \
  " C-m \; \
  split-window -v \; \
  send-keys "\
    sleep 30 ; \
    cd $DATA && \
    ${chainweb-data}/bin/chainweb-data server \
      --port 9696 \
      -f \
      --service-host=127.0.0.1 \
      --service-port=1848 \
      --p2p-host=127.0.0.1 \
      --p2p-port=1790 \
      --dbhost 127.0.0.1 \
      --dbuser=$(whoami) \
      --dbname=chainweb-data \
      -m \
    " C-m \;
EOF
    chmod +x $out/bin/start-kadena
  '';

  env = pkgs.buildEnv { inherit name; paths = buildInputs; };
};

in {
  inherit
    pact-src pact-drv pact
    chainweb-node-src chainweb-node-drv chainweb-node
    chainweb-data-src chainweb-data
    start-kadena;
}
