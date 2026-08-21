#!/usr/bin/env bash
# Copyright 2026 Michele Moser
# SPDX-License-Identifier: Apache-2.0
set -Eeuo pipefail

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "$TEST_DIR/../.." && pwd)
plugin_command="$PROJECT_DIR/libexec/wasalight-plugin"

registry() {
    LANGUAGE=$1 WASALIGHT_PLUGIN_ROOT="$PROJECT_DIR/plugins" \
        WASALIGHT_VERSION_OVERRIDE=2026.08.21.1 \
        WASALIGHT_PLUGIN_TEST_MODE=show \
        python3 "$plugin_command" list --json
}

english=$(registry en_US.UTF-8)
italian=$(registry it_IT.UTF-8)

python3 - "$english" "$italian" <<'PY'
import json
import sys

english = {item["id"]: item for item in json.loads(sys.argv[1])}
italian = {item["id"]: item for item in json.loads(sys.argv[2])}

assert english["ssh"]["name"] == "SSH access"
assert italian["ssh"]["name"] == "Accesso SSH"
assert english["vnc"]["description"].startswith("Remote sharing")
assert italian["vnc"]["description"].startswith("Condivisione remota")
assert english["companion"]["controls"][0]["label"] == "Service active"
assert italian["companion"]["controls"][0]["label"] == "Servizio attivo"
assert english["companion"]["actions"][-1]["label"] == "Update"
assert italian["companion"]["actions"][-1]["label"] == "Aggiorna"
assert english["companion"]["actions"][3]["confirm"] == "Stop Bitfocus Companion?"
assert italian["companion"]["actions"][3]["confirm"] == "Fermare Bitfocus Companion?"
PY

printf 'Localizzazione manifest plugin verificata.\n'
