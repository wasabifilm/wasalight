#!/usr/bin/env bash
# Project entry point. It automatically uses the single .deb in packages/.

set -Eeuo pipefail

PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALLER="$PROJECT_DIR/bin/chamsys_install_ubuntu.sh"
args=("$@")
deb_supplied=0

for arg in "$@"; do
    if [[ "$arg" == -h || "$arg" == --help ]]; then
        exec "$INSTALLER" "$@"
    fi
    [[ "$arg" == *.deb ]] && deb_supplied=1
done

if ((deb_supplied == 0)); then
    shopt -s nullglob
    packages=("$PROJECT_DIR"/packages/*.deb)
    shopt -u nullglob
    case ${#packages[@]} in
        0)
            printf 'Pacchetto MagicQ non trovato in %s\n' "$PROJECT_DIR/packages" >&2
            printf 'Lo script può continuare senza MagicQ, ma l’applicazione non verrà installata.\n' >&2
            ;;
        1) args+=("${packages[0]}") ;;
        *)
            printf 'Sono presenti più pacchetti .deb. Specifica quello da usare sulla riga di comando.\n' >&2
            exit 2
            ;;
    esac
fi

exec "$INSTALLER" "${args[@]}"
