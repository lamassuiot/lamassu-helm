#!/usr/bin/env bash
# Three Lamassu EST RAs: ECDSA -> composite cross-signing -> native PQ trust -> PQ.
# All cryptography and HTTPS use OpenSSL with baentsch/hybrid-provider loaded.
set -Eeuo pipefail
umask 077
export LC_ALL=C

help() {
    cat <<'EOF'
Uso: pqc-showcase.sh <subcomando> [opciones]

  provider      Compila baentsch/hybrid-provider/main o carga un modulo existente.
  check         Comprueba claves/CSRs locales y capacidades del KMS (solo lectura).
  check-mtls    Comprueba si el servidor solicita certificado TLS de cliente.
  prepare       Crea 2 raices, 6 registros CA y exactamente 3 RAs EST.
  baseline      Inscribe un dispositivo Legacy, uno migrable y uno PQC con mTLS.
  migrate       Renueva el migrable con MLDSA65-RSA3072-PSS y cadena cross-signada.
  switch-trust  Cambia a la cadena nativa bajo Root PQC sin renovar el certificado.
  finalize      Renueva a ML-DSA-65 puro y retira la compatibilidad anterior.
  verify        Comprueba cadenas, confianza, RAs, identidad activa y revocacion.
  status        Muestra el estado local, sin usar la red.
  run           Ejecuta las fases pendientes, guardando el progreso.
  self-test     Prueba CSR composite, cross-signing y parser HTTP sin API Lamassu.

Opciones (antes o despues del subcomando):
  --server URL            https://host[:puerto]; tambien SERVER. Se guarda.
  --state-dir DIR         Tambien PQC_SHOWCASE_DIR. Por defecto:
                          ${XDG_STATE_HOME:-$HOME/.local/state}/lamassu/pqc-showcase
  --prefix ID             Prefijo de recursos (por defecto pqc). Se guarda.
  --engine ID             Motor KMS; tambien PQC_ENGINE_ID. Se autodetecta.
  --openssl BIN           OpenSSL >=3.5; tambien OPENSSL_BIN.
  --openssl-root DIR      Headers/librerias para compilar; OPENSSL_ROOT_DIR.
  --provider-module FILE  hybrid.so existente; tambien HYBRID_PROVIDER_MODULE.
  --provider-ref REF      Ref de hybrid-provider para un nuevo build; default main.
  --tls-codepoint VALUE   Default 0xFE02 (Lamassu Go), o upstream. Solo al compilar.
  --tls-ca FILE           CA TLS del servidor; tambien TLS_CA_FILE.
  -k, --insecure          Omite validar el certificado TLS; tambien INSECURE=true.
  --timeout SECONDS       Timeout por peticion HTTPS; default 45.
  -h, --help

Autenticacion administrativa: export ACCESS_TOKEN='...'; nunca se guarda.
Sin ACCESS_TOKEN se requiere un despliegue que permita administracion sin token.
Las peticiones EST usan sus certificados de cliente, sin el token administrativo.

Ejemplo:
  export SERVER=https://lab.lamassu.io ACCESS_TOKEN='...' TLS_CA_FILE=/ruta/root.crt
  ./scripts/pqc-showcase.sh provider
  ./scripts/pqc-showcase.sh self-test
  ./scripts/pqc-showcase.sh prepare
  ./scripts/pqc-showcase.sh baseline
  ./scripts/pqc-showcase.sh migrate
  ./scripts/pqc-showcase.sh switch-trust
  ./scripts/pqc-showcase.sh finalize
  ./scripts/pqc-showcase.sh status

Requisitos: Bash >=4, jq, OpenSSL >=3.5, timeout, flock y utilidades GNU.
Compilar provider requiere git, cmake y compilador C. Se fija y registra el commit
de main usado. Se carga default+hybrid y se conserva el parche del codepoint TLS.
Un modulo externo debe usar un codepoint TLS compatible con el servidor.

No modifica el ingress ni la configuracion TLS del servidor. trust/*.pem son los
almacenes del validador local de demo. No exporta claves privadas de las CAs ni
borra recursos. Las claves de los dispositivos se guardan con permisos privados.
El perfil PQC rechaza RSA/ECDSA; la API no dispone de una allowlist PQC completa.
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null || die "Falta el comando: $1"; }
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die 'Se necesita Bash >=4.'

COMMAND=''
SERVER=${SERVER:-}
STATE_DIR=${PQC_SHOWCASE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/lamassu/pqc-showcase}
PREFIX=${PQC_PREFIX:-}
ENGINE=${PQC_ENGINE_ID:-}
OPENSSL=${OPENSSL_BIN:-openssl}
OPENSSL_ROOT=${OPENSSL_ROOT_DIR:-}
MODULE=${HYBRID_PROVIDER_MODULE:-}
PROVIDER_REF=main
TLS_CODEPOINT=0xFE02
TLS_CA=${TLS_CA_FILE:-}
INSECURE=${INSECURE:-false}
REQUEST_TIMEOUT=45
while (($#)); do
    case "$1" in
        -h|--help|help) help; exit 0 ;;
        --server|--state-dir|--prefix|--engine|--openssl|--openssl-root|--provider-module|--provider-ref|--tls-codepoint|--tls-ca|--timeout)
            (($# >= 2)) || die "Falta un valor para $1"
            case "$1" in
                --server) SERVER=$2 ;; --state-dir) STATE_DIR=$2 ;; --prefix) PREFIX=$2 ;;
                --engine) ENGINE=$2 ;; --openssl) OPENSSL=$2 ;; --openssl-root) OPENSSL_ROOT=$2 ;;
                --provider-module) MODULE=$2 ;; --provider-ref) PROVIDER_REF=$2 ;;
                --tls-codepoint) TLS_CODEPOINT=$2 ;; --tls-ca) TLS_CA=$2 ;; --timeout) REQUEST_TIMEOUT=$2 ;;
            esac
            shift 2 ;;
        -k|--insecure) INSECURE=true; shift ;;
        provider|check|check-mtls|prepare|baseline|migrate|switch-trust|finalize|verify|status|run|self-test)
            [[ -z $COMMAND ]] || die 'Indica un solo subcomando.'
            COMMAND=$1; shift ;;
        *) die "Argumento desconocido: $1" ;;
    esac
done
[[ -n $COMMAND ]] || { help; exit 2; }
[[ $INSECURE == true || $INSECURE == false ]] || die 'INSECURE debe ser true o false.'
[[ $REQUEST_TIMEOUT =~ ^[1-9][0-9]*$ ]] || die '--timeout debe ser un entero positivo.'
if [[ $TLS_CODEPOINT != upstream ]]; then
    [[ $TLS_CODEPOINT =~ ^0x[0-9a-fA-F]{1,4}$ ]] || die '--tls-codepoint: usa 0xFE02 o upstream.'
    ((TLS_CODEPOINT > 0)) || die 'Codepoint TLS invalido.'
fi
for tool in jq openssl mktemp flock timeout base64 sha256sum dd awk; do need "$tool"; done
need "$OPENSSL"
OPENSSL=$(command -v "$OPENSSL")
mkdir -p "$STATE_DIR"
STATE_DIR=$(cd "$STATE_DIR" && pwd -P)
STATE=$STATE_DIR/state.json
exec 9>"$STATE_DIR/.lock"
flock -n 9 || die 'Otro proceso esta usando este directorio de estado.'
TMP=$(mktemp -d "${TMPDIR:-/tmp}/pqc-showcase.XXXXXXXX")
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT
trap 'log "Interrumpido. Conserva el estado y repite el subcomando para recuperar el progreso."; exit 130' INT TERM
trap 'log "Fallo en linea $LINENO. El estado se conserva en $STATE_DIR."' ERR

sget() { jq -er "$1" "$STATE"; }
sset() {
    local filter=$1 next; shift
    next=$(mktemp "$STATE_DIR/.state.XXXXXXXX")
    jq "$@" "$filter" "$STATE" >"$next"
    mv "$next" "$STATE"
}
phase() { jq -r '.phase' "$STATE"; }
id() { printf '%s-%s' "$PREFIX" "$1"; }
b64() { base64 -w0 "$1"; }
ossl() { "$OPENSSL" "$@"; }
if [[ ! -f $STATE ]]; then
    jq -n --arg run "$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')" \
        '{schema:1,run_id:$run,phase:0,profiles:{},keys:{},ca_fingerprints:{},devices:{},transactions:{},checks:{}}' >"$STATE"
fi
[[ $(sget '.schema') == 1 ]] || die 'Version de estado incompatible.'
SAVED_SERVER=$(jq -r '.server // ""' "$STATE")
SAVED_PREFIX=$(jq -r '.prefix // ""' "$STATE")
SERVER=${SERVER:-$SAVED_SERVER}; SERVER=${SERVER%/}
PREFIX=${PREFIX:-${SAVED_PREFIX:-pqc}}
[[ $PREFIX =~ ^[a-z][a-z0-9-]{0,31}$ ]] || die 'Prefijo invalido: usa a-z, 0-9 y guion (1-32 caracteres).'
[[ -z $SAVED_SERVER || $SERVER == "$SAVED_SERVER" ]] || die 'El estado pertenece a otro servidor; usa otro --state-dir.'
[[ -z $SAVED_PREFIX || $PREFIX == "$SAVED_PREFIX" ]] || die 'El estado pertenece a otro prefijo; usa otro --state-dir.'
[[ ${ACCESS_TOKEN:-} != *$'\n'* && ${ACCESS_TOKEN:-} != *$'\r'* ]] || die 'ACCESS_TOKEN contiene saltos de linea.'
sset '.server=$server | .prefix=$prefix' --arg server "$SERVER" --arg prefix "$PREFIX"
RUN_ID=$(sget '.run_id')
mkdir -p "$STATE_DIR"/{ca,devices,trust,evidence/http,provider}
HTTP_SEQ=0
HTTP_CODE=''
TRACE_TLS=false
LAST_TLS_TRACE=''

provider() {
    local source=$STATE_DIR/provider/source commit root digest previous info external=false
    MODULE=${MODULE:-$(jq -r '.provider.module // ""' "$STATE")}
    if [[ -z $MODULE ]]; then
        for tool in git cmake cc; do need "$tool"; done
        if [[ ! -d $source/.git ]]; then
            [[ ! -e $source ]] || die "Clone incompleto en $source; usa otro --state-dir."
            git clone --quiet https://github.com/baentsch/hybrid-provider.git "$source"
            git -C "$source" checkout --quiet "$PROVIDER_REF"
        fi
        commit=$(git -C "$source" rev-parse HEAD)
        if [[ $TLS_CODEPOINT != upstream ]]; then
            # Adapt only the one composite used in this showcase, on our own clone.
            awk -v cp="$TLS_CODEPOINT" '
                /X\(mldsa65_rsa3072_pss,/ { row=1 }
                row && /COMPOSITE_TIER_STANDARD/ {
                    if (sub(/COMPOSITE_TIER_STANDARD,[[:space:]]*(0x[0-9a-fA-F]+|0),/,
                            "COMPOSITE_TIER_STANDARD, " cp ",")) n++
                    row=0
                }
                { print }
                END { if (n != 1) exit 42 }
            ' "$source/composite_prov.h" >"$TMP/composite_prov.h" || die 'Cambio la tabla upstream; no se puede adaptar el codepoint.'
            cp "$TMP/composite_prov.h" "$source/composite_prov.h"
        fi
        root=${OPENSSL_ROOT:-$(dirname "$(dirname "$(readlink -f "$OPENSSL")")")}
        log "Compilando baentsch/hybrid-provider ${commit:0:12} con $OPENSSL..."
        if ! cmake -S "$source" -B "$source/build" -DCMAKE_BUILD_TYPE=Release \
                -DHYBRID_COMPOSITE=ON -DOPENSSL_ROOT_DIR="$root" >"$STATE_DIR/provider/build.log" 2>&1; then
            die "Fallo cmake; revisa $STATE_DIR/provider/build.log"
        fi
        if ! cmake --build "$source/build" --target hybrid-provider -j 2 >>"$STATE_DIR/provider/build.log" 2>&1; then
            die "Fallo la compilacion; revisa $STATE_DIR/provider/build.log"
        fi
        git -C "$source" diff -- composite_prov.h >"$STATE_DIR/provider/lamassu-tls.patch"
        MODULE=$source/build/hybrid.so
        info=$(jq -n --arg commit "$commit" --arg ref "$PROVIDER_REF" --arg cp "$TLS_CODEPOINT" \
            '{repo:"https://github.com/baentsch/hybrid-provider",commit:$commit,requested_ref:$ref,tls_codepoint:$cp}')
    else
        info=$(jq '.provider // {}' "$STATE")
        if [[ $(jq -r '.provider.module // ""' "$STATE") != "$(realpath "$MODULE")" ]]; then
            external=true
            info='{"repo":"https://github.com/baentsch/hybrid-provider","external":true,"tls_codepoint":"external: comprobar compatibilidad con Lamassu"}'
        fi
    fi
    MODULE=$(realpath "$MODULE")
    [[ -f $MODULE && $MODULE != *'"'* && $MODULE != *'$'* && $MODULE != *$'\n'* && $MODULE != *$'\r'* ]] || die 'Ruta del modulo invalida.'
    cat >"$STATE_DIR/openssl.cnf" <<EOF
openssl_conf = openssl_init
config_diagnostics = 1
[openssl_init]
providers = providers
[providers]
default = default_provider
hybrid = hybrid_provider
[default_provider]
activate = 1
[hybrid_provider]
module = "$MODULE"
activate = 1
EOF
    export OPENSSL_CONF=$STATE_DIR/openssl.cnf
    ossl list -key-managers >"$TMP/key-managers.txt"
    grep -q 'mldsa65_rsa3072_pss' "$TMP/key-managers.txt" || die 'Falta el composite; compila con HYBRID_COMPOSITE=ON.'
    digest=$(sha256sum "$MODULE" | awk '{print $1}')
    previous=$(jq -r '.provider.sha256 // ""' "$STATE")
    if [[ -n $previous && $previous != "$digest" ]] && (( $(phase) >= 2 )); then
        die 'El provider cambio despues del baseline; conserva el modulo o usa otro estado.'
    fi
    info=$(jq --arg module "$MODULE" --arg digest "$digest" --arg version "$(ossl version)" \
        '. + {module:$module,sha256:$digest,openssl:$version}' <<<"$info")
    sset '.provider=$info' --argjson info "$info"
    [[ $external == false ]] || log 'Modulo externo: su codepoint TLS debe coincidir con el del servidor.'
    log "Provider listo: $MODULE"
}

# HTTP bodies in this API are JSON or PEM. dd handles framing without storing
# binary chunks in Bash variables. Reject truncated bodies, including chunked.
parse_http() {
    local input=$1 output=$2 line header name value length='' chunked=false chunk size got fd ended=false
    exec {fd}<"$input"
    while :; do
        IFS= read -r line <&"$fd" || { exec {fd}<&-; return 1; }
        line=${line%$'\r'}
        [[ $line =~ ^HTTP/1\.[01]\ ([0-9]{3})(\ |$) ]] || { exec {fd}<&-; return 1; }
        HTTP_CODE=${BASH_REMATCH[1]}
        length=''; chunked=false; ended=false
        while IFS= read -r header <&"$fd"; do
            header=${header%$'\r'}
            if [[ -z $header ]]; then ended=true; break; fi
            name=${header%%:*}; value=${header#*:}; value=${value# }
            case "${name,,}" in content-length) length=$value ;; transfer-encoding) [[ ${value,,} != *chunked* ]] || chunked=true ;; esac
        done
        [[ $ended == true ]] || { exec {fd}<&-; return 1; }
        [[ $HTTP_CODE == 100 ]] || break
    done
    : >"$output"
    if [[ $chunked == true ]]; then
        while :; do
            IFS= read -r chunk <&"$fd" || { exec {fd}<&-; return 1; }
            chunk=${chunk%$'\r'}; chunk=${chunk%%;*}
            [[ $chunk =~ ^[0-9a-fA-F]{1,7}$ ]] || { exec {fd}<&-; return 1; }
            size=$((16#$chunk))
            ((size <= 16777216)) || { exec {fd}<&-; return 1; }
            if ((size == 0)); then
                # Trailers end with an empty line.
                while IFS= read -r line <&"$fd"; do
                    [[ $line != $'\r' && -n $line ]] || { exec {fd}<&-; return 0; }
                done
                exec {fd}<&-; return 1
            fi
            dd bs=1 count="$size" status=none <&"$fd" >"$TMP/http.chunk"
            got=$(wc -c <"$TMP/http.chunk")
            ((got == size)) || { exec {fd}<&-; return 1; }
            cat "$TMP/http.chunk" >>"$output"
            IFS= read -r line <&"$fd" || { exec {fd}<&-; return 1; }
            [[ $line == $'\r' ]] || { exec {fd}<&-; return 1; }
        done
    elif [[ -n $length ]]; then
        [[ $length =~ ^[0-9]+$ && ${#length} -lt 9 ]] || { exec {fd}<&-; return 1; }
        size=$((10#$length))
        ((size <= 16777216)) || { exec {fd}<&-; return 1; }
        dd bs=1 count="$size" status=none <&"$fd" >"$output"
        got=$(wc -c <"$output")
        exec {fd}<&-
        ((got == size))
    else
        cat <&"$fd" >"$output"
        exec {fd}<&-
    fi
}

# request METHOD PATH OUT [BODY_FILE] [CERT] [KEY] [CHAIN] [json|est]
# Transport succeeds independently of HTTP status. api() enforces 2xx; negatives
# inspect HTTP_CODE and the application's error, never an arbitrary TLS failure.
request() {
    local method=$1 path=$2 output=$3 body=${4:-} cert=${5:-} key=${6:-} chain=${7:-} mode=${8:-json}
    local host port base host_header connect name wire raw tlslog verify_flag=-verify_hostname
    [[ $SERVER =~ ^https://(\[[^]]+\]|[a-zA-Z0-9.-]+)(:([0-9]+))?(/[^\?\#\ ]*)?$ ]] || die 'Indica --server https://host[:puerto] (sin credenciales/query).'
    host=${BASH_REMATCH[1]}; port=${BASH_REMATCH[3]:-443}; base=${BASH_REMATCH[4]:-}
    host_header=$host:$port
    connect=$host:$port
    host=${host#[}; host=${host%]}
    [[ $host != *:* && ! $host =~ ^[0-9.]+$ ]] || verify_flag=-verify_ip
    [[ $path != *$'\r'* && $path != *$'\n'* && $base != *$'\r'* && $base != *$'\n'* ]] || die 'Ruta HTTP invalida.'
    HTTP_SEQ=$((HTTP_SEQ + 1)); name=$(date +%s%N)-$HTTP_SEQ
    wire=$TMP/request; raw=$TMP/response.raw; tlslog=$STATE_DIR/evidence/http/$name.tls.log
    {
        printf '%s %s%s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n' "$method" "${base%/}" "$path" "$host_header"
        if [[ $mode == est ]]; then
            printf 'Accept: application/x-pem-file\r\n'
        else
            printf 'Accept: application/json\r\n'
            [[ -z ${ACCESS_TOKEN:-} ]] || printf 'Authorization: Bearer %s\r\n' "$ACCESS_TOKEN"
        fi
        if [[ -n $body ]]; then
            [[ $mode == est ]] && printf 'Content-Type: application/pkcs10\r\n' || printf 'Content-Type: application/json\r\n'
            printf 'Content-Length: %s\r\n' "$(wc -c <"$body")"
        fi
        printf '\r\n'
        [[ -z $body ]] || cat "$body"
    } >"$wire"
    local -a args=(s_client -connect "$connect" -servername "$host" -quiet -ign_eof -ignore_unexpected_eof -alpn http/1.1)
    LAST_TLS_TRACE=''
    if [[ $TRACE_TLS == true || -n $cert ]]; then
        LAST_TLS_TRACE=$STATE_DIR/evidence/http/$name.handshake.log
        args+=(-msg -msgfile "$LAST_TLS_TRACE")
    fi
    [[ $INSECURE == true ]] || args+=(-verify_return_error "$verify_flag" "$host")
    [[ -z $TLS_CA ]] || args+=(-CAfile "$TLS_CA" -no-CApath -no-CAstore)
    [[ -z $cert ]] || args+=(-cert "$cert" -key "$key" -cert_chain "$chain")
    if ! timeout "$REQUEST_TIMEOUT" "$OPENSSL" "${args[@]}" <"$wire" >"$raw" 2>"$tlslog"; then
        tail -c 1600 "$tlslog" >&2
        die "Fallo TLS/transporte. Revisa mTLS, el codepoint composite y $tlslog"
    fi
    parse_http "$raw" "$output" || die "Respuesta HTTP incompleta o invalida: $method $path"
    printf '%s\t%s\t%s\n' "$HTTP_CODE" "$method" "$path" >>"$STATE_DIR/evidence/http/requests.tsv"
}
api() {
    request "$@"
    if [[ $HTTP_CODE != 2* ]]; then
        head -c 1200 "$3" >&2
        if [[ $HTTP_CODE == 401 || $HTTP_CODE == 403 ]]; then
            log ''
            log 'Revisa ACCESS_TOKEN y sus permisos para esta operacion. INSECURE=true solo cambia la validacion TLS.'
        fi
        die "HTTP $HTTP_CODE: $1 $2"
    fi
}
list_all() {
    local path=$1 output=$2 bookmark='' encoded next seen='|'
    printf '[]\n' >"$output"
    while :; do
        encoded=$(jq -rn --arg value "$bookmark" '$value|@uri')
        api GET "$path${bookmark:+?bookmark=$encoded}" "$TMP/page.json"
        jq -e '.list | type == "array"' "$TMP/page.json" >/dev/null || die 'Formato de lista API inesperado.'
        jq -s '.[0] + .[1].list' "$output" "$TMP/page.json" >"$TMP/list.next"
        mv "$TMP/list.next" "$output"
        next=$(jq -r '.next // ""' "$TMP/page.json")
        [[ -n $next ]] || break
        [[ $seen != *"|$next|"* ]] || die 'La API repite el bookmark.'
        seen+="$next|"; bookmark=$next
    done
}
owned() { jq -e --arg run "$RUN_ID" '.metadata.showcase_run == $run' "$1" >/dev/null || die 'El ID pertenece a otro showcase; usa otro --prefix.'; }
require_phase() {
    local current; current=$(phase)
    ((current >= $1 && current <= ${2:-5})) || die 'Orden de fases: prepare, baseline, migrate, switch-trust, finalize. Consulta status.'
}
ca() { printf '%s/ca/%s.crt' "$STATE_DIR" "$1"; }
device_id() {
    case "$1" in legacy) id pump-legacy-001 ;; migration) id robot-upgrade-001 ;; pure) id sensor-pqc-001 ;; esac
}
key_csr() {
    local stem=$1 kind=$2 cn=$3
    mkdir -p "$(dirname "$stem")"
    if [[ ! -s $stem.key ]]; then
        case "$kind" in
            classic) ossl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$TMP/generated.key" ;;
            composite) ossl genpkey -algorithm mldsa65_rsa3072_pss -out "$TMP/generated.key" ;;
            pq) ossl genpkey -algorithm ML-DSA-65 -out "$TMP/generated.key" ;;
        esac
        mv "$TMP/generated.key" "$stem.key"
    fi
    ossl req -new -key "$stem.key" -subj "/CN=$cn/O=PQC Showcase" -out "$TMP/generated.csr"
    ossl req -in "$TMP/generated.csr" -verify -noout >/dev/null
    mv "$TMP/generated.csr" "$stem.csr"
}
spki() { ossl x509 -in "$1" -pubkey -noout | ossl pkey -pubin -outform DER | sha256sum | awk '{print $1}'; }
key_spki() { ossl pkey -in "$1" -pubout -outform DER | sha256sum | awk '{print $1}'; }
serial() { ossl x509 -in "$1" -noout -serial | cut -d= -f2 | tr '[:lower:]' '[:upper:]' | sed 's/^0*//'; }
fingerprint() { ossl x509 -in "$1" -outform DER | sha256sum | awk '{print $1}'; }
decode_cert() { jq -er "$2" "$1" | base64 -d >"$3"; ossl x509 -in "$3" -noout >/dev/null; }

probe_mtls() {
    # Anonymous health request: no bootstrap certificate/key or token is used.
    # RequestClientCert must advertise CertificateRequest even to this client.
    TRACE_TLS=true
    request GET /api/ca/health "$TMP/mtls-health" '' '' '' '' est
    TRACE_TLS=false
    [[ $HTTP_CODE == 200 ]] || die "No se puede comprobar mTLS: health HTTP $HTTP_CODE."
    if [[ ! -f $LAST_TLS_TRACE ]] || ! grep -q 'CertificateRequest' "$LAST_TLS_TRACE"; then
        log 'El servidor no envia CertificateRequest: OpenSSL no puede presentar el certificado de cliente.'
        log 'Revisa TLSOption clientAuthType=RequestClientCert y Gateway tls.options[traefik.io/tls-options]=default.'
        log 'El fork Traefik pqc-3.7.7 puede ignorar esa opcion; el repositorio usa pqc-3.7.15.'
        die "mTLS no disponible en el endpoint. Traza: $LAST_TLS_TRACE"
    fi
    log 'Preflight mTLS OK: el servidor solicita certificado TLS de cliente.'
}

check() {
    provider
    local kind requested
    for kind in classic composite pq; do key_csr "$TMP/preflight-$kind" "$kind" preflight; done
    probe_mtls
    api GET /api/kms/v1/engines "$TMP/engines.json"
    requested=${ENGINE:-$(jq -r '.engine_id // ""' "$STATE")}
    ENGINE=$(jq -r --arg requested "$requested" '
        def supports($t;$s): any(.supported_key_types[]; .type==$t and (.sizes|index($s))!=null);
        [.[] | select(($requested=="" or .id==$requested) and supports("ECDSA";256)
          and supports("ML-DSA";65) and supports("Composite-ML-DSA-RSA";3))]
        | sort_by(.default != true) | .[0].id // empty' "$TMP/engines.json")
    [[ -n $ENGINE ]] || die 'Ningun motor seleccionado soporta ECDSA/256, ML-DSA/65 y Composite-ML-DSA-RSA/3.'
    [[ $(jq -r '.engine_id // ""' "$STATE") == '' || $(sget '.engine_id') == "$ENGINE" ]] || die 'No se puede cambiar el motor de un showcase existente.'
    sset '.engine_id=$id' --arg id "$ENGINE"
    log "Preflight OK: motor $ENGINE. baseline comprobara el mTLS real hasta el DMS."
}

ensure_profile() {
    local role=$1 is_ca=$2 hours=$3 pq=$4 name count profile_id
    name="$PREFIX showcase $RUN_ID $role"
    list_all /api/ca/v1/profiles "$TMP/profiles.json"
    jq --arg name "$name" '[.[]|select(.name==$name)]' "$TMP/profiles.json" >"$TMP/matches.json"
    count=$(jq length "$TMP/matches.json"); ((count <= 1)) || die "Perfiles duplicados: $role"
    if ((count == 1)); then
        jq '.[0]' "$TMP/matches.json" >"$TMP/profile.json"
    else
        jq -n --arg name "$name" --arg run "$RUN_ID" --arg duration "${hours}h" --argjson ca "$is_ca" --argjson pq "$pq" '
          {name:$name,description:("PQC showcase "+$run),validity:{type:"Duration",duration:$duration},
           sign_as_ca:$ca,honor_subject:true,subject:{},honor_key_usage:false,
           key_usage:(if $ca then ["CertSign","CRLSign"] else ["DigitalSignature"] end),
           honor_extended_key_usages:false,extended_key_usages:(if $ca then [] else ["ClientAuth"] end),
           honor_extensions:false,crypto_enforcement:{enabled:($ca|not),allow_rsa_keys:false,
             allow_ecdsa_keys:($pq|not),allowed_ecdsa_key_sizes:[256]}}' >"$TMP/body.json"
        api POST /api/ca/v1/profiles "$TMP/profile.json" "$TMP/body.json"
    fi
    profile_id=$(jq -er '.id' "$TMP/profile.json")
    sset '.profiles[$role]=$id' --arg role "$role" --arg id "$profile_id"
}
ensure_key() {
    local role=$1 algorithm=$2 size=$3 count uri
    list_all /api/kms/v1/keys "$TMP/keys.json"
    jq --arg run "$RUN_ID" --arg role "$role" '[.[]|select(.metadata.showcase_run==$run and .metadata.showcase_role==$role)]' "$TMP/keys.json" >"$TMP/matches.json"
    count=$(jq length "$TMP/matches.json"); ((count <= 1)) || die "Claves duplicadas: $role"
    if ((count == 1)); then jq '.[0]' "$TMP/matches.json" >"$TMP/key.json"; else
        jq -n --arg role "$role" --arg run "$RUN_ID" --arg prefix "$PREFIX" --arg algorithm "$algorithm" \
          --argjson size "$size" --arg engine "$ENGINE" '{algorithm:$algorithm,size:$size,engine_id:$engine,
          name:($prefix+" showcase "+$role),tags:["pqc-showcase",$prefix],metadata:{showcase_run:$run,showcase_role:$role}}' >"$TMP/body.json"
        api POST /api/kms/v1/keys "$TMP/key.json" "$TMP/body.json"
    fi
    jq -e --arg alg "$algorithm" --arg engine "$ENGINE" --argjson size "$size" \
       '.algorithm==$alg and .size==$size and .engine_id==$engine and .has_private_key==true' "$TMP/key.json" >/dev/null || die "Clave incompatible: $role"
    uri=$(jq -r '"pkcs11:token-id="+.engine_id+";id="+.key_id+";type=private"' "$TMP/key.json")
    sset '.keys[$role]=$key + {pkcs11_uri:$uri}' --arg role "$role" --argjson key "$(cat "$TMP/key.json")" --arg uri "$uri"
}
ensure_ca() {
    local role=$1 key_role=$2 parent=${3:-} profile=${4:-device-pq} cert_hash previous cert_profile duration count
    # Resource authorization can deny a nonexistent ID before the controller
    # could return 404. Discover readable CAs through the authorized list route.
    # Never reinterpret a 403 as proof that a resource does not exist.
    list_all /api/ca/v1/cas "$TMP/cas.json"
    jq --arg id "$(id "$role")" '[.[]|select(.id==$id)]' "$TMP/cas.json" >"$TMP/ca-matches.json"
    count=$(jq length "$TMP/ca-matches.json")
    ((count <= 1)) || die "IDs de CA duplicados en el listado: $role"
    if ((count == 0)); then
        previous=$(jq -r --arg role "$role" '.ca_fingerprints[$role] // ""' "$STATE")
        [[ -z $previous ]] || die "La CA $role ya estaba registrada pero no aparece en el listado autorizado. Revisa permisos o si fue eliminada."
        cert_profile=ca-root; duration=87600h
        [[ -z $parent ]] || { cert_profile=ca-intermediate; duration=26280h; }
        jq -n --arg id "$(id "$role")" --arg parent "${parent:+$(id "$parent")}" --arg cn "$(id "$key_role")" \
          --arg run "$RUN_ID" --arg role "$role" --arg engine "$ENGINE" --argjson key "$(jq --arg r "$key_role" '.keys[$r]' "$STATE")" \
          --arg profile "$(jq -r --arg r "$profile" '.profiles[$r]' "$STATE")" \
          --arg cert_profile "$(jq -r --arg r "$cert_profile" '.profiles[$r]' "$STATE")" --arg duration "$duration" '
          {id:$id,parent_id:$parent,subject:{common_name:$cn,organization:"PQC Showcase"},engine_id:$engine,
           key_metadata:{key_id:$key.pkcs11_uri,type:$key.algorithm,bits:$key.size},
           ca_expiration:{type:"Duration",duration:$duration},profile_id:$profile,ca_issuance_profile_id:$cert_profile,
           metadata:{showcase_run:$run,showcase_role:$role}}' >"$TMP/body.json"
        api POST /api/ca/v1/cas "$TMP/ca.json" "$TMP/body.json"
    else
        jq '.[0]' "$TMP/ca-matches.json" >"$TMP/ca.json"
    fi
    owned "$TMP/ca.json"
    [[ $(jq -r '.certificate.status' "$TMP/ca.json") == ACTIVE ]] || die "CA no activa: $role"
    decode_cert "$TMP/ca.json" '.certificate.certificate' "$TMP/ca.crt"
    cert_hash=$(fingerprint "$TMP/ca.crt")
    previous=$(jq -r --arg role "$role" '.ca_fingerprints[$role] // ""' "$STATE")
    [[ -z $previous || $previous == "$cert_hash" ]] || die "Cambio el certificado de la CA $role."
    mv "$TMP/ca.crt" "$(ca "$role")"
    sset '.ca_fingerprints[$role]=$hash' --arg role "$role" --arg hash "$cert_hash"
}
ra_body() {
    local role=$1 issuer=ica-legacy root=root-classic profile=device-classic
    [[ $role != pure ]] || { issuer=ica-pure; root=root-pq; profile=device-pq; }
    jq -n --arg id "$(id "ra-$role")" --arg role "$role" --arg run "$RUN_ID" \
      --arg issuer "$(id "$issuer")" --arg root "$(id "$root")" \
      --arg profile "$(jq -r --arg r "$profile" '.profiles[$r]' "$STATE")" '
      {id:$id,name:("PQC Showcase - "+$role),metadata:{showcase_run:$run,cohort:$role},settings:{
       issuance_profile_id:$profile,server_keygen_settings:{enabled:false},
       enrollment_settings:{protocol:"EST_RFC7030",enrollment_ca:$issuer,registration_mode:"JITP",
        enable_replaceable_enrollment:false,verify_csr_signature:true,
        est_rfc7030_settings:{auth_mode:"CLIENT_CERTIFICATE",client_certificate_settings:{
         validation_cas:[$issuer],chain_level_validation:-1,allow_expired:false}},
        device_provisioning_profile:{icon:"Laptop",icon_color:"#0066CC",
         tags:["pqc-showcase",$role],metadata:{showcase_run:$run,cohort:$role}}},
       reenrollment_settings:{est_rfc7030_settings:{auth_mode:"CLIENT_CERTIFICATE"},
        additional_validation_cas:[],revoke_on_reenrollment:true,reenrollment_delta:"25h",enable_expired_renewal:false},
       ca_distribution_settings:{include_system_ca:false,include_enrollment_ca:true,managed_cas:[$root]}}}'
}
ensure_provisioning_profile() {
    local role=$1 path
    path=/api/dmsmanager/v1/dms/$(id "ra-$role")
    api GET "$path" "$TMP/provisioning-ra.json"
    owned "$TMP/provisioning-ra.json"
    # Older showcase RAs omitted fields required by CreateDeviceInput. Complete
    # only missing values; preserve custom icons and the current migration phase.
    if jq -e '.settings.enrollment_settings.device_provisioning_profile |
        ((.icon // "") | length)>0 and ((.icon_color // "") | length)>0' \
        "$TMP/provisioning-ra.json" >/dev/null; then
        return 0
    fi
    jq '.settings.enrollment_settings.device_provisioning_profile |=
        (if ((.icon // "") | length)==0 then .icon="Laptop" else . end |
         if ((.icon_color // "") | length)==0 then .icon_color="#0066CC" else . end)' \
        "$TMP/provisioning-ra.json" >"$TMP/provisioning-ra.next"
    api PUT "$path" "$TMP/provisioning-ra.updated" "$TMP/provisioning-ra.next"
    log "Perfil de aprovisionamiento completado: $(id "ra-$role") (icon/icon_color)."
}
same_bridge() {
    local cross native options
    cross=$(ca ica-migration-cross); native=$(ca ica-migration-native)
    [[ $(spki "$cross") == "$(spki "$native")" ]] || die 'Las intermedias cross y nativa no comparten la clave publica.'
    [[ $(ossl x509 -in "$cross" -noout -subject -nameopt RFC2253) == "$(ossl x509 -in "$native" -noout -subject -nameopt RFC2253)" ]] || die 'Las intermedias no comparten Subject.'
    [[ $(ossl x509 -in "$cross" -noout -ext subjectKeyIdentifier) == "$(ossl x509 -in "$native" -noout -ext subjectKeyIdentifier)" ]] || die 'Las intermedias no comparten SKI.'
}
bundles() {
    local role issuer root current; current=$(phase)
    for role in legacy migration pure; do
        issuer=ica-legacy; root=root-classic
        if [[ $role == pure ]]; then issuer=ica-pure; root=root-pq; fi
        if [[ $role == migration ]] && ((current >= 3)); then
            if ((current == 3)); then issuer=ica-migration-cross; else root=root-pq; issuer=ica-migration-native; fi
            ((current < 5)) || issuer=ica-pure
        fi
        cat "$(ca "$issuer")" "$(ca "$root")" >"$STATE_DIR/trust/$role-chain.pem"
        cp "$(ca "$root")" "$STATE_DIR/trust/$role-roots.pem"
    done
}
prepare() {
    check
    # Detect namespace collisions before creating profiles, keys or authorities.
    local role count
    list_all /api/ca/v1/cas "$TMP/existing-cas.json"
    for role in root-classic root-pq ica-legacy ica-migration-cross ica-migration-native ica-pure; do
        jq --arg id "$(id "$role")" '.[]|select(.id==$id)' "$TMP/existing-cas.json" >"$TMP/existing.json"
        [[ ! -s $TMP/existing.json ]] || owned "$TMP/existing.json"
    done
    list_all /api/dmsmanager/v1/dms "$TMP/existing-ras.json"
    for role in legacy migration pure; do
        jq --arg id "$(id "ra-$role")" '.[]|select(.id==$id)' "$TMP/existing-ras.json" >"$TMP/existing.json"
        [[ ! -s $TMP/existing.json ]] || owned "$TMP/existing.json"
        get_device "$role" "$TMP/existing-device.json"
    done
    ensure_profile ca-root true 87600 false
    ensure_profile ca-intermediate true 26280 false
    ensure_profile device-classic false 24 false
    ensure_profile device-pq false 24 true
    ensure_key root-classic ECDSA 256
    ensure_key root-pq ML-DSA 65
    ensure_key ica-legacy ECDSA 256
    ensure_key ica-migration Composite-ML-DSA-RSA 3
    ensure_key ica-pure ML-DSA 65
    ensure_ca root-classic root-classic '' ca-intermediate
    ensure_ca root-pq root-pq '' ca-intermediate
    ensure_ca ica-legacy ica-legacy root-classic device-classic
    ensure_ca ica-migration-cross ica-migration root-classic
    ensure_ca ica-migration-native ica-migration root-pq
    ensure_ca ica-pure ica-pure root-pq
    list_all /api/dmsmanager/v1/dms "$TMP/ras.json"
    for role in legacy migration pure; do
        jq --arg id "$(id "ra-$role")" '[.[]|select(.id==$id)]' "$TMP/ras.json" >"$TMP/matches.json"
        count=$(jq length "$TMP/matches.json")
        if ((count == 0)); then
            ra_body "$role" >"$TMP/body.json"
            api POST /api/dmsmanager/v1/dms "$TMP/ra.json" "$TMP/body.json"
        else jq '.[0]' "$TMP/matches.json" >"$TMP/ra.json"; fi
        owned "$TMP/ra.json"
        ensure_provisioning_profile "$role"
    done
    same_bridge
    sset '.phase=([.phase,1]|max)'
    bundles
    log 'Preparado: 2 raices, 3 intermedias logicas, 6 registros CA, 5 claves CA y 3 RAs.'
}

bootstrap() {
    local role=$1 stem=$STATE_DIR/devices/$1/bootstrap kind=classic issuer=ica-legacy profile=device-classic
    [[ $role != pure ]] || { kind=pq; issuer=ica-pure; profile=device-pq; }
    key_csr "$stem" "$kind" "$(device_id "$role")"
    if [[ ! -s $stem.crt ]]; then
        jq -n --arg csr "$(b64 "$stem.csr")" --arg profile "$(jq -r --arg p "$profile" '.profiles[$p]' "$STATE")" \
            '{csr:$csr,profile_id:$profile}' >"$TMP/body.json"
        api POST "/api/ca/v1/cas/$(id "$issuer")/certificates/sign" "$TMP/bootstrap.json" "$TMP/body.json"
        decode_cert "$TMP/bootstrap.json" '.certificate' "$stem.crt"
    fi
}
subject_attributes() {
    # Go's pkix.Name reorders the generated CN/O RDNs when issuing a certificate.
    # Compare complete escaped RDN lines by numeric OID, retaining all values,
    # duplicates and multi-valued RDN groupings instead of splitting on commas.
    ossl "$1" -in "$2" -noout -subject -nameopt RFC2253,sep_multiline,oid |
        sed '1d' | sort
}
check_identity() {
    local cert=$1 key=$2 issuer=$3 csr=$4 cert_subject csr_subject
    [[ $(spki "$cert") == "$(key_spki "$key")" ]] || die 'El certificado no corresponde a la clave del CSR.'
    cert_subject=$(subject_attributes x509 "$cert") || die 'No se puede leer el Subject del certificado.'
    csr_subject=$(subject_attributes req "$csr") || die 'No se puede leer el Subject del CSR.'
    [[ -n $cert_subject && $cert_subject == "$csr_subject" ]] || die 'El Subject emitido no coincide con los atributos del CSR.'
    ossl verify -no-CAfile -no-CApath -no-CAstore -partial_chain -trusted "$(ca "$issuer")" -purpose sslclient "$cert" >/dev/null
    ossl x509 -in "$cert" -noout -text >"$cert.txt"
}
get_device() {
    local role=$1 output=$2
    list_all /api/devmanager/v1/devices "$TMP/devices.json"
    jq --arg id "$(device_id "$role")" '[.[]|select(.id==$id)] | .[0] // null' "$TMP/devices.json" >"$output"
    if [[ $(jq -r 'type' "$output") != null ]]; then
        jq -e --arg run "$RUN_ID" --arg ra "$(id "ra-$role")" \
            '.metadata.showcase_run==$run and .dms_owner==$ra' "$output" >/dev/null || die 'El dispositivo existente no pertenece a esta RA/showcase.'
    fi
}
active_serial() { jq -r '.identity as $i | $i.versions[($i.active_version|tostring)] // empty' "$1"; }
finish_identity() {
    local role=$1 stage=$2 issuer=$3 tx=$1-$2 stem=$STATE_DIR/devices/$1/$2 remote_serial
    check_identity "$stem.crt" "$stem.key" "$issuer" "$stem.csr"
    get_device "$role" "$TMP/device.json"
    remote_serial=$(active_serial "$TMP/device.json")
    [[ -n $remote_serial ]] || die 'La API no ha vinculado una identidad activa al dispositivo.'
    api GET "/api/ca/v1/certificates/$remote_serial" "$TMP/active.json"
    decode_cert "$TMP/active.json" '.certificate' "$TMP/active.crt"
    [[ $(fingerprint "$stem.crt") == "$(fingerprint "$TMP/active.crt")" ]] || die 'El certificado recibido no es la identidad activa remota.'
    sset '.transactions[$tx].done=true | .transactions[$tx].serial=$serial |
          .devices[$role]={stage:$stage,issuer:$issuer,serial:$serial}' \
        --arg tx "$tx" --arg serial "$remote_serial" --arg role "$role" --arg stage "$stage" --arg issuer "$issuer"
    log "Identidad emitida: $role/$stage SN=$remote_serial"
}
enroll() {
    local role=$1 stage=$2 kind=$3 issuer=$4 operation=$5 auth_stem=$6 auth_issuer=$7
    local tx=$role-$stage stem=$STATE_DIR/devices/$role/$stage pending remote_serial old_serial
    key_csr "$stem" "$kind" "$(device_id "$role")"
    if [[ $(jq -r --arg tx "$tx" '.transactions[$tx].done // false' "$STATE") == true ]]; then
        check_identity "$stem.crt" "$stem.key" "$issuer" "$stem.csr"; return
    fi
    get_device "$role" "$TMP/device.json"
    remote_serial=$(active_serial "$TMP/device.json")
    pending=$(jq -r --arg tx "$tx" '.transactions|has($tx)' "$STATE")
    if [[ $pending == true && -n $remote_serial ]]; then
        api GET "/api/ca/v1/certificates/$remote_serial" "$TMP/recovered.json"
        decode_cert "$TMP/recovered.json" '.certificate' "$TMP/recovered.crt"
        if [[ $(spki "$TMP/recovered.crt") == "$(key_spki "$stem.key")" ]]; then
            cp "$TMP/recovered.crt" "$stem.crt"
            finish_identity "$role" "$stage" "$issuer"; return
        fi
        old_serial=$(jq -r --arg tx "$tx" '.transactions[$tx].old_serial // ""' "$STATE")
        [[ $old_serial == "$remote_serial" && $(jq -r '.status' "$TMP/recovered.json") == ACTIVE ]] || die 'Operacion parcial: la identidad remota no coincide o ya fue revocada. No se repetira la renovacion.'
    elif [[ $operation == simpleenroll && $(jq -r type "$TMP/device.json") != null ]]; then
        die 'Alta parcial/existente sin identidad recuperable. Revisa el dispositivo antes de continuar.'
    fi
    if [[ $pending == false ]]; then
        [[ $operation != simpleenroll || -z $remote_serial ]] || die 'El dispositivo ya tiene una identidad.'
        sset '.transactions[$tx]={done:false,operation:$operation,old_serial:$old}' \
            --arg tx "$tx" --arg operation "$operation" --arg old "$remote_serial"
    fi
    ossl req -in "$stem.csr" -outform DER | base64 -w0 >"$TMP/est.body"
    request POST "/api/dmsmanager/.well-known/est/$(id "ra-$role")/$operation" "$TMP/est.crt" \
        "$TMP/est.body" "$auth_stem.crt" "$auth_stem.key" "$(ca "$auth_issuer")" est
    if [[ $HTTP_CODE != 2* ]]; then
        head -c 1200 "$TMP/est.crt" >&2
        printf '\n' >&2
        if grep -q 'DMS auth mode not supported' "$TMP/est.crt"; then
            if [[ -f $LAST_TLS_TRACE ]] && ! grep -q 'CertificateRequest' "$LAST_TLS_TRACE"; then
                log 'El servidor no solicita certificado de cliente. Revisa RequestClientCert y la version/opciones de Traefik.'
            else
                log 'Comprueba auth_mode=CLIENT_CERTIFICATE en la RA y el reenvio del certificado por Traefik/Envoy hasta el DMS.'
            fi
            log "Traza del handshake: $LAST_TLS_TRACE"
        fi
        die "EST HTTP $HTTP_CODE. Se conserva la operacion pendiente para recuperar la identidad si llego a vincularse."
    fi
    mv "$TMP/est.crt" "$stem.crt"
    finish_identity "$role" "$stage" "$issuer"
}
negative_est() {
    local name=$1 role=$2 csr=$3 pattern=$4 auth_stem=${5:-} issuer=${6:-} operation=${7:-simplereenroll}
    [[ $(jq -r --arg name "$name" '.checks[$name].pass // false' "$STATE") != true ]] || return 0
    ossl req -in "$csr" -outform DER | base64 -w0 >"$TMP/negative.body"
    if [[ -n $auth_stem ]]; then
        request POST "/api/dmsmanager/.well-known/est/$(id "ra-$role")/$operation" "$TMP/negative.json" \
            "$TMP/negative.body" "$auth_stem.crt" "$auth_stem.key" "$(ca "$issuer")" est
    else
        request POST "/api/dmsmanager/.well-known/est/$(id "ra-$role")/$operation" "$TMP/negative.json" "$TMP/negative.body" '' '' '' est
    fi
    [[ $HTTP_CODE == 400 || $HTTP_CODE == 401 || $HTTP_CODE == 403 || $HTTP_CODE == 500 ]] || die "Negativa $name: HTTP inesperado $HTTP_CODE"
    grep -Eiq "$pattern" "$TMP/negative.json" || { cat "$TMP/negative.json" >&2; die "Negativa $name: el error no demuestra el rechazo esperado."; }
    cp "$TMP/negative.json" "$STATE_DIR/evidence/$name.json"
    sset '.checks[$name]={pass:true,expected:"reject",http:$status}' --arg name "$name" --arg status "$HTTP_CODE"
    log "PASS $name (rechazo EST comprobado)"
}
baseline() {
    require_phase 1 2; provider
    probe_mtls
    local role kind issuer stage
    for role in legacy migration pure; do ensure_provisioning_profile "$role"; done
    key_csr "$TMP/noauth" classic "$(id noauth-probe)"
    negative_est no-client-certificate migration "$TMP/noauth.csr" 'DMS auth mode not supported|missing client certificate|no client certificate|unauthoriz' '' '' simpleenroll
    for role in legacy migration pure; do
        bootstrap "$role"
        kind=classic; issuer=ica-legacy; stage=classic
        [[ $role != pure ]] || { kind=pq; issuer=ica-pure; stage=pq; }
        enroll "$role" "$stage" "$kind" "$issuer" simpleenroll "$STATE_DIR/devices/$role/bootstrap" "$issuer"
    done
    key_csr "$STATE_DIR/devices/pure/rejected-classic" classic "$(device_id pure)"
    negative_est pq-rejects-ecdsa pure "$STATE_DIR/devices/pure/rejected-classic.csr" 'public key is ECDSA' "$STATE_DIR/devices/pure/pq" ica-pure
    sset '.phase=2'; bundles; verify
}
update_migration() {
    local issuer=$1 additional=$2 managed=$3 label=$4
    api GET "/api/dmsmanager/v1/dms/$(id ra-migration)" "$TMP/ra.json"
    owned "$TMP/ra.json"
    jq --arg issuer "$(id "$issuer")" --arg prefix "$PREFIX" --arg label "$label" \
      --arg profile "$(sget '.profiles["device-pq"]')" --argjson additional "$additional" --argjson managed "$managed" '
      .settings.issuance_profile_id=$profile | .settings.issuance_profile=null |
      .settings.enrollment_settings.enrollment_ca=$issuer |
      .settings.enrollment_settings.est_rfc7030_settings.client_certificate_settings.validation_cas=[$issuer] |
      .settings.reenrollment_settings.additional_validation_cas=($additional|map($prefix+"-"+.)) |
      .settings.ca_distribution_settings.managed_cas=($managed|map($prefix+"-"+.)) |
      .metadata.phase=$label' "$TMP/ra.json" >"$TMP/ra.next"
    api PUT "/api/dmsmanager/v1/dms/$(id ra-migration)" "$TMP/updated.json" "$TMP/ra.next"
    cp "$TMP/ra.next" "$STATE_DIR/evidence/ra-migration-$label.json"
}
migrate() {
    require_phase 2 3; provider
    update_migration ica-migration-cross '["ica-legacy"]' '["root-classic","root-pq","ica-migration-native"]' composite
    enroll migration composite composite ica-migration-cross simplereenroll "$STATE_DIR/devices/migration/classic" ica-legacy
    negative_est classic-revoked-est migration "$STATE_DIR/devices/migration/composite.csr" 'revoked' "$STATE_DIR/devices/migration/classic" ica-legacy
    sset '.phase=3'; bundles; verify
}
switch_trust() {
    require_phase 3 4; provider
    local before after; before=$(fingerprint "$STATE_DIR/devices/migration/composite.crt")
    update_migration ica-migration-native '[]' '["root-pq"]' native-trust
    sset '.devices.migration.issuer="ica-migration-native" | .phase=4'
    bundles; verify
    after=$(fingerprint "$STATE_DIR/devices/migration/composite.crt")
    [[ $before == "$after" ]] || die 'Cambio inesperado del certificado durante switch-trust.'
    log "Mismo certificado composite, nuevo camino de confianza. SHA256=$after"
}
finalize() {
    require_phase 4 5; provider
    update_migration ica-pure '["ica-migration-native"]' '["root-pq"]' finalizing
    enroll migration pq pq ica-pure simplereenroll "$STATE_DIR/devices/migration/composite" ica-migration-native
    negative_est composite-revoked-est migration "$STATE_DIR/devices/migration/pq.csr" 'revoked' "$STATE_DIR/devices/migration/composite" ica-migration-native
    update_migration ica-pure '[]' '["root-pq"]' pqc
    sset '.phase=5'; bundles; verify
}
verify_path() {
    local name=$1 cert=$2 issuer=$3 root=$4 expected=${5:-accept} accepted=false output=$STATE_DIR/evidence/$1.log
    if ossl verify -no-CAfile -no-CApath -no-CAstore -purpose sslclient -trusted "$(ca "$root")" \
        -untrusted "$(ca "$issuer")" "$cert" >"$output" 2>&1; then accepted=true; fi
    if [[ $expected == accept ]]; then
        [[ $accepted == true ]] || { cat "$output" >&2; die "Fallo la cadena $name"; }
    else
        [[ $accepted == false ]] || die "Se acepto la cadena negativa $name"
        grep -Eiq 'unable to get (local )?issuer certificate|unable to verify the first certificate|self-signed certificate in certificate chain' "$output" || die "El rechazo de $name no demuestra falta de confianza."
    fi
    sset '.checks[$name]={pass:true,expected:$expected}' --arg name "$name" --arg expected "$expected"
    log "PASS $name ($expected)"
}
verify_revoked() {
    local tx=$1 sn
    sn=$(jq -er --arg tx "$tx" '.transactions[$tx].serial' "$STATE")
    api GET "/api/ca/v1/certificates/$sn" "$TMP/status.json"
    [[ $(jq -r '.status' "$TMP/status.json") == REVOKED ]] || die "La identidad $tx no esta revocada."
}
verify() {
    require_phase 2; provider; same_bridge
    local current role stem issuer sn remote_sn expected_issuer profile managed additional
    current=$(phase)
    verify_path legacy "$STATE_DIR/devices/legacy/classic.crt" ica-legacy root-classic
    verify_path pure "$STATE_DIR/devices/pure/pq.crt" ica-pure root-pq
    if ((current >= 3)); then
        verify_path composite-via-classic "$STATE_DIR/devices/migration/composite.crt" ica-migration-cross root-classic
        verify_path composite-via-pq "$STATE_DIR/devices/migration/composite.crt" ica-migration-native root-pq
        verify_path cross-without-classic-root "$STATE_DIR/devices/migration/composite.crt" ica-migration-cross root-pq reject
        verify_revoked migration-classic
    fi
    if ((current >= 5)); then
        verify_path migration-pure "$STATE_DIR/devices/migration/pq.crt" ica-pure root-pq
        verify_revoked migration-composite
    fi
    for role in legacy migration pure; do
        stem=$STATE_DIR/devices/$role/$(jq -r --arg role "$role" '.devices[$role].stage' "$STATE")
        issuer=$(jq -r --arg role "$role" '.devices[$role].issuer' "$STATE")
        check_identity "$stem.crt" "$stem.key" "$issuer" "$stem.csr"
        get_device "$role" "$TMP/device.json"
        sn=$(jq -r --arg role "$role" '.devices[$role].serial' "$STATE")
        remote_sn=$(active_serial "$TMP/device.json")
        [[ -n $sn && $sn == "$remote_sn" ]] || die "La identidad activa remota no coincide: $role"
        api GET "/api/ca/v1/certificates/$sn" "$TMP/active-status.json"
        [[ $(jq -r '.status' "$TMP/active-status.json") == ACTIVE ]] || die "Identidad operativa no activa: $role"
        api GET "/api/dmsmanager/v1/dms/$(id "ra-$role")" "$TMP/ra.json"; owned "$TMP/ra.json"
        expected_issuer=$(id "$issuer")
        [[ $(jq -r '.settings.enrollment_settings.enrollment_ca' "$TMP/ra.json") == "$expected_issuer" ]] || die "Emisor de RA inesperado: $role"
        profile=device-classic; managed='["root-classic"]'; additional='[]'
        if [[ $role == pure || ( $role == migration && $current -ge 3 ) ]]; then
            profile=device-pq; managed='["root-pq"]'
        fi
        if [[ $role == migration && $current == 3 ]]; then
            managed='["root-classic","root-pq","ica-migration-native"]'; additional='["ica-legacy"]'
        fi
        jq -e --arg prefix "$PREFIX" --arg profile "$(jq -r --arg p "$profile" '.profiles[$p]' "$STATE")" \
          --argjson managed "$managed" --argjson additional "$additional" '
          .settings as $s |
          $s.issuance_profile_id==$profile and $s.server_keygen_settings.enabled==false and
          $s.enrollment_settings.verify_csr_signature==true and
          $s.enrollment_settings.est_rfc7030_settings.auth_mode=="CLIENT_CERTIFICATE" and
          $s.reenrollment_settings.est_rfc7030_settings.auth_mode=="CLIENT_CERTIFICATE" and
          $s.reenrollment_settings.revoke_on_reenrollment==true and
          ($s.reenrollment_settings.additional_validation_cas|sort)==($additional|map($prefix+"-"+.)|sort) and
          $s.ca_distribution_settings.include_system_ca==false and
          $s.ca_distribution_settings.include_enrollment_ca==true and
          ($s.ca_distribution_settings.managed_cas|sort)==($managed|map($prefix+"-"+.)|sort)' \
          "$TMP/ra.json" >/dev/null || die "La configuracion de $role no coincide con la fase de migracion."
        request GET "/api/dmsmanager/.well-known/est/$(id "ra-$role")/cacerts" "$STATE_DIR/evidence/$role-cacerts.pem" '' '' '' '' est
        [[ $HTTP_CODE == 200 ]] || die "No se pudo descargar cacerts: $role"
        ossl crl2pkcs7 -nocrl -certfile "$STATE_DIR/evidence/$role-cacerts.pem" -outform DER >"$TMP/cacerts.p7"
    done
    jq '{phase,provider,devices,checks}' "$STATE" >"$STATE_DIR/evidence/summary.json"
    log "Verificacion OK. Cadenas, estado de revocacion y RAs comprobados. Evidencias: $STATE_DIR/evidence"
}
status() {
    jq --arg dir "$STATE_DIR" '{server,prefix,phase:(["new","prepared","baseline","composite","native-trust","pqc"][.phase]),
        state_dir:$dir,engine:.engine_id,provider,devices,pending:[.transactions|to_entries[]|select(.value.done!=true)|.key]}' "$STATE"
}
run_all() {
    (( $(phase) >= 1 )) || prepare
    (( $(phase) >= 2 )) || baseline
    (( $(phase) >= 3 )) || migrate
    (( $(phase) >= 4 )) || switch_trust
    (( $(phase) >= 5 )) || finalize
    verify
}

self_test() {
    provider
    local dir=$TMP/self-test name kind parent keyrole flags result
    mkdir -p "$dir"
    # Real keys and signatures: composite public keys, signatures and both paths.
    for name in root-classic root-pq cross native leaf pure; do
        parent=''; keyrole=$name; kind=pq
        case "$name" in
            root-classic) kind=classic ;;
            cross) kind=composite; keyrole=bridge; parent=root-classic ;;
            native) kind=composite; keyrole=bridge; parent=root-pq ;;
            leaf) kind=composite; parent=cross ;;
            pure) parent=root-pq ;;
        esac
        key_csr "$dir/$keyrole" "$kind" "$keyrole"
        if [[ $name == leaf || $name == pure ]]; then
            printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n' >"$dir/extensions"
        else
            printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' >"$dir/extensions"
        fi
        printf 'subjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n' >>"$dir/extensions"
        local -a sign_args=(-signkey "$dir/$keyrole.key")
        if [[ -n $parent ]]; then
            keyrole=$parent; [[ $parent != cross ]] || keyrole=bridge
            sign_args=(-CA "$dir/$parent.crt" -CAkey "$dir/$keyrole.key")
        fi
        keyrole=$name; [[ $name != cross && $name != native ]] || keyrole=bridge
        local -a subject_args=()
        # Emulate the Subject ordering of Lamassu's Go X.509 encoder.
        [[ $name != leaf ]] || subject_args=(-subj /O=PQC\ Showcase/CN=leaf)
        ossl x509 -req -in "$dir/$keyrole.csr" "${sign_args[@]}" -set_serial "$((RANDOM * 32768 + RANDOM + 1))" \
            -days 2 -extfile "$dir/extensions" "${subject_args[@]}" -out "$dir/$name.crt"
    done
    [[ $(subject_attributes x509 "$dir/leaf.crt") == "$(subject_attributes req "$dir/leaf.csr")" ]] || die 'Self-test: Subject reordenado rechazado.'
    local changed_subject
    for changed_subject in '/CN=another-device/O=PQC Showcase' '/CN=leaf/O=Another organization' '/CN=leaf' '/CN=leaf/O=PQC Showcase/O=PQC Showcase'; do
        ossl req -new -key "$dir/leaf.key" -subj "$changed_subject" -out "$dir/changed-subject.csr"
        [[ $(subject_attributes x509 "$dir/leaf.crt") != "$(subject_attributes req "$dir/changed-subject.csr")" ]] || die 'Self-test: se acepto un cambio de atributos del Subject.'
    done
    log 'PASS offline Subject reordenado; rechazo de CN/organizacion modificados, ausentes o duplicados.'
    [[ $(spki "$dir/cross.crt") == "$(spki "$dir/native.crt")" ]] || die 'Self-test: SPKI diferentes.'
    for name in cross native; do
        parent=root-classic; [[ $name != native ]] || parent=root-pq
        ossl verify -no-CAfile -no-CApath -no-CAstore -purpose sslclient -trusted "$dir/$parent.crt" \
            -untrusted "$dir/$name.crt" "$dir/leaf.crt" || die "Self-test: fallo la cadena $name"
        log "PASS offline composite-via-$name"
    done
    if ossl verify -no-CAfile -no-CApath -no-CAstore -purpose sslclient -trusted "$dir/root-pq.crt" \
        -untrusted "$dir/cross.crt" "$dir/leaf.crt" >"$dir/rejected.log" 2>&1; then die 'Self-test: se acepto una cadena sin su raiz.'; fi
    grep -q 'unable to get local issuer certificate' "$dir/rejected.log" || die 'Self-test: rechazo por causa inesperada.'
    ossl verify -no-CAfile -no-CApath -no-CAstore -purpose sslclient -trusted "$dir/root-pq.crt" "$dir/pure.crt"
    printf 'HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nPQC\r\n0\r\n\r\n' >"$dir/http"
    parse_http "$dir/http" "$dir/body" || die 'Self-test: parser chunked.'
    [[ $HTTP_CODE == 200 && $(cat "$dir/body") == PQC ]] || die 'Self-test: cuerpo chunked incorrecto.'
    printf 'HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nPQC' >"$dir/http"
    if parse_http "$dir/http" "$dir/body"; then die 'Self-test: se acepto un cuerpo HTTP truncado.'; fi
    log 'PASS offline confianza negativa, ML-DSA puro, HTTP chunked y rechazo de truncamiento.'
    log 'Self-test OK. No se han creado recursos en Lamassu.'
}

case "$COMMAND" in
    provider) provider ;; check) check ;; check-mtls) provider; probe_mtls ;; prepare) prepare ;; baseline) baseline ;;
    migrate) migrate ;; switch-trust) switch_trust ;; finalize) finalize ;; verify) verify ;;
    status) status ;; run) run_all ;; self-test) self_test ;;
esac
