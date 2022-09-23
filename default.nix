args@{
  rev    ? "7a94fcdda304d143f9a40006c033d7e190311b54"
, sha256 ? "0d643wp3l77hv2pmg2fi7vyxn4rwy0iyr8djcw1h5x72315ck9ik"

, pkgs   ? import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
    inherit sha256; }) {
    config.allowUnfree = true;
    config.allowBroken = false;
  }

, node-db-dir         ? "$HOME/.local/share/chainweb-node/mainnet01"
, node-log-file       ? "$HOME/Library/Logs/chainweb-node.log"
, data-db-dir         ? "$HOME/.local/share/chainweb-data"
, data-log-file       ? "$HOME/Library/Logs/chainweb-data.log"
, node-p2p-port       ? 1790
, node-service-port   ? 1848

, replay-db-dir       ?
  "/Volumes/G-DRIVE/ChainState/kadena/chainweb-node-replay/mainnet01"
, replay-p2p-port     ? 1791
, replay-service-port ? 1884
}:

let

##########################################################################
#
# Config and command-line options for chainweb-node
#

primary-node-config = configFile "error" {
  allowReadsInLocal = true;
  headerStream = true;
  throttling = {
    global = 10000;
  };
};

primary-node-options = {
  config-file = "${primary-node-config}";
  database-directory = node-db-dir;
  disable-node-mining = true;
  bootstrap-reachability = 0;
  p2p-port = node-p2p-port;
  service-port = node-service-port;
};

replay-node-config = configFile "info" {
  allowReadsInLocal = true;
  headerStream = true;
  onlySyncPact = true;
  validateHashesOnReplay = true;
  cuts = {
    pruneChainDatabase = "headers-checked";
  };
  transactionIndex = {
    enabled = false;
  };
  p2p = {
    private = true;
    ignoreBootstrapNodes = true;
  };
};

replay-node-options = {
  config-file = "${replay-node-config}";
  database-directory = replay-db-dir;
  disable-node-mining = true;
  bootstrap-reachability = 0;
  p2p-port = replay-p2p-port;
  service-port = replay-service-port;
};

##########################################################################
#
# Source code for Pact, Chainweb and other components
#

pact-info = {
  branch = "master";
  rev = "4fc970ffc1a8fc41769920c88dc4818f4b5380cb";
  sha256 = "01rz4mn5p4q5wv40qajw5gsbbw7z5q1sfxc1fg9hvlv2iv7f8ahl";
};

pact-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "pact";
  inherit (pact-info) rev sha256;
  # rev = "4fc970ffc1a8fc41769920c88dc4818f4b5380cb";
  # sha256 = "01rz4mn5p4q5wv40qajw5gsbbw7z5q1sfxc1fg9hvlv2iv7f8ahl";
  # date = "2022-08-31T16:17:05-06:00";
};

# pact-src = ~/kadena/current/pact;

chainweb-node-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "chainweb-node";
  rev = "71eb31f431739fff962e24dae4b28a6fcdd5f543";
  sha256 = "1mi25pcdmgi70c2ahwkazkfjsfrxsjy1v7n38drknma9j1j2h05a";
  # date = "2022-08-29T10:41:38+02:00";
};

# chainweb-node-src = ~/kadena/chainweb-node;

chainweb-data-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "chainweb-data";
  rev = "52f865935255ff8124b815e67c7c9cbb250c82eb";
  sha256 = "04lc1km36klgyahp2af8djnxd35lhsjr377a8r5n24i0jfrbadkq";
  # date = "2022-09-23T13:01:11-07:00";
};

# integration-tests-src = pkgs.fetchFromGitHub {
#   private = true;
#   owner = "kadena-io";
#   repo = "integration-tests";
#   rev = "b223788d878e8d7c7f7e4e03f114ae61e3976eeb";
#   sha256 = "011mczhhq7fqk784raa7zg1g9fd2gknph01265hyf4vzmxgr0y6r";
#   # date = "2022-08-04T20:20:13-07:00";
# };

# Because this is a private GitHub repository, the simplest thing is to use a
# local clone.
integration-tests-src = ~/kadena/integration-tests;

devnet-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "devnet";
  rev = "488399c7a493f94888793f4e2b61b966f8b77e48";
  sha256 = "1rhinp5535iscnfaix4z1bmz5l3w6k4x4ha2j5q44cih9xwd3i94";
  # date = "2022-09-22T16:59:12-07:00";
};

##########################################################################
#
# Source and executable derivations for the above
#

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

chainweb-data = pkgs.haskell.lib.compose.justStaticExecutables
  ((import chainweb-data-src {}).overrideAttrs (_: {
     preConfigure = ''
       sed -i -e 's/ghc-options:    -threaded/-- ghc-options:    -threaded/' \
           chainweb-data.cabal
     '';
   }));

devnet-drv = pkgs.stdenv.mkDerivation rec {
  name = "devnet-drv-${version}";
  version = "1.0";

  src = devnet-src;

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
  '';

  installPhase = ''
    mkdir -p $out
    cp -pR .env $out
    cp -pR * $out
  '';
};

##########################################################################
#
# Configuration files for Chainweb-node
#

toYAML = name: data:
  pkgs.writeText name (pkgs.lib.generators.toYAML {} data);

configFile = defaultLogLevel: chainweb: toYAML "chainweb-node.config" {
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
      log_level = defaultLogLevel;
    };

    filter = {
      rules = [
        { key = "component";
          value = "cut-monitor";
          level = "info"; }
        { key = "component";
          value = "pact";
          level = "info"; }
      ];
      default = defaultLogLevel;
    };
  };

  inherit chainweb;
};

options-to-str = opts: with pkgs.lib;
    "--config-file ${primary-node-config} "
    # Note that ${opts.database-directory} cannot be used here, or it would
    # copy the entire directory into the Nix store.
  + "--database-directory '" + opts.database-directory + "' "
  + optionalString opts.disable-node-mining "--disable-node-mining "
  + "--bootstrap-reachability ${builtins.toString opts.bootstrap-reachability} "
  + "--p2p-port ${builtins.toString opts.p2p-port} "
  + "--service-port ${builtins.toString opts.service-port} "
;

##########################################################################
#
# Scripts, the primary output of this Nix file
#

startup-script = with pkgs; writeText "start-kadena.sh" ''
#!${bash}/bin/bash

DATA="${builtins.toString data-db-dir}"

if [[ ! -f "$DATA/pgdata/PG_VERSION" ]]; then
    mkdir -p "$DATA/pgdata"
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" initdb
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" \
        -l "${builtins.toString data-log-file}" start
    sleep 5
    ${postgresql}/bin/createdb chainweb-data || echo "OK: db already exists"
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    echo "Postgres failed to start; see ${builtins.toString data-log-file}"
    exit 1
fi

cd $DATA

if [[ ! -f scripts/richlist.sh ]]; then
    mkdir -p scripts
    cp ${src}/scripts/richlist.sh scripts/richlist.sh
fi

NODE=$(dirname "${builtins.toString node-db-dir}")
if [[ ! -d ${builtins.toString node-db-dir} ]]; then
    mkdir -p "$NODE"
fi

exec ${tmux}/bin/tmux new-session \; \
  send-keys "\
    cd \"$NODE\" && \
    ${chainweb-node}/bin/chainweb-node \
      ${options-to-str primary-node-options} \
      2>&1 | tee ${builtins.toString node-log-file} \
  " C-m \; \
  split-window -v \; \
  send-keys "\
    sleep 30 ; \
    cd \"$DATA\" && \
    ${chainweb-data}/bin/chainweb-data server \
      --port 9696 \
      -f \
      --service-host=127.0.0.1 \
      --service-port=${builtins.toString primary-node-options.service-port} \
      --p2p-host=127.0.0.1 \
      --p2p-port=${builtins.toString primary-node-options.p2p-port} \
      --dbhost 127.0.0.1 \
      --dbuser=$(whoami) \
      --dbname=chainweb-data \
      -m \
    " C-m \;
'';

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
    cp -p ${startup-script} $out/bin/start-kadena
    chmod +x $out/bin/start-kadena
  '';
};

run-chainweb-replay = with pkgs; stdenv.mkDerivation rec {
  name = "replay-kadena-${version}";
  version = "1.0";

  src = ./.;

  buildInputs = [
    chainweb-node
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p ${startup-script} $out/bin/start-kadena
    chmod +x $out/bin/start-kadena
  '';
};

start-devnet = with pkgs; stdenv.mkDerivation rec {
  name = "start-devnet-${version}";
  version = "1.0";

  src = ./.;

  propagatedBuildInputs = [
    integration-tests-deps
    nodejs-14_x
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cat <<'EOF' > $out/bin/start-devnet
#!${bash}/bin/bash

TESTS=$(mktemp -d -t integration-tests-XXX)

mkdir -p "$TESTS/devnet"

cp -pR "${devnet-drv}"/.env "$TESTS/devnet"
cp -pR "${devnet-drv}"/* "$TESTS/devnet"

cd "$TESTS/devnet"

DEVNET=$(docker ps --filter 'name=devnet' | wc -l)
if (( DEVNET < 4 )); then
    cd devnet
    docker compose pull
    docker compose build pact
    docker compose build chainweb-node
    echo "Starting Devnet in $TESTS/devnet"
    docker compose up -d
    cd ..
else
    echo Devnet appears to already be running
fi
EOF
    chmod +x $out/bin/start-devnet
  '';
};

integration-tests = with pkgs; stdenv.mkDerivation rec {
  name = "integration-tests-${version}";
  version = "1.0";

  src = integration-tests-src;

  buildInputs = [
    node2nix
  ];

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    rm -fr node_modules package-lock.json \
        node-env.nix node-packages.nix default.nix
    node2nix --nodejs-14 --development
  '';

  installPhase = ''
    mkdir -p $out
    cp -pR * $out
  '';
};

integration-tests-deps =
  (import "${integration-tests}" { inherit pkgs; }).nodeDependencies;

run-integration-tests = with pkgs; stdenv.mkDerivation rec {
  name = "run-integration-tests-${version}";
  version = "1.0";

  src = ./.;

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cat <<'EOF' > $out/bin/run-integration-tests
#!${bash}/bin/bash

TESTS=$(mktemp -d -t integration-tests-XXX)

export NODE_PATH=${integration-tests-deps}/lib/node_modules

mkdir -p "$TESTS"

ln -s "$NODE_PATH" "$TESTS"
cp -pR "${integration-tests-src}"/.taprc "$TESTS"
cp -pR "${integration-tests-src}"/* "$TESTS"

cd "$TESTS"

if ${nodejs-14_x}/bin/npm run test
then
    # rm -fr "$TESTS"
    echo "Successful test results are in $TESTS"
else
    echo "Failed test results are in $TESTS"
fi
EOF
    chmod +x $out/bin/run-integration-tests
  '';
};

in {
  inherit
    pact-drv pact
    chainweb-node-drv chainweb-node run-chainweb-replay
    chainweb-data startup-script start-kadena
    start-devnet
    integration-tests run-integration-tests;
}
