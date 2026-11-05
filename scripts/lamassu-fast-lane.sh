#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

dist=
kube=
KUBE_CONTEXT=""
KUBECTL_CONTEXT_ARGS=()
HELM_CONTEXT_ARGS=()

DOMAIN=dev.lamassu.io
DOMAIN_OVERRIDE=false
NAMESPACE=lamassu-dev
NAMESPACE_OVERRIDE=false
NON_INTERACTIVE=false
OTEL=false
HTTPS_PORT=443
HTTP_PORT=80
GATEWAY_IP=""
LAMASSU_CHART_PATH="lamassuiot/lamassu"
LAMASSU_USE_LOCAL_PATH=false
SAMPLE_DATA=false
HELM_INSTALL_TIMEOUT="${HELM_INSTALL_TIMEOUT:-15m}"

SOFTHSM_CHART_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)/charts/softhsm"
WITH_HSM=false
# NetHSM (nitrokey/nethsm:testing) ships amd64-only images, so it is skipped
# on ARM clusters even when --with-hsm is set. SoftHSM/PKCS#11 still deploy.
WITH_NETHSM=true
SOFTHSM_SSH_PRIVATE_KEY_FILE=""
SOFTHSM_SSH_PUBLIC_KEY=""
SOFTHSM_LABEL="lamassuHSM"
SOFTHSM_PIN="1234"
SOFTHSM_SLOT="0"
SOFTHSM_SO_PIN="5432"
# The KMS downloads the NetHSM PKCS#11 module at runtime so no custom KMS image is needed.
NETHSM_PKCS11_VERSION="v2.2.0"
NETHSM_TOKEN_LABEL="LocalHSM"
NETHSM_OPERATOR_PASSPHRASE="0123456789"
NETHSM_UNLOCK_PASSPHRASE=$(
    shuf -er -n30 {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)
NETHSM_ADMIN_PASSPHRASE=$(
    shuf -er -n30 {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)
NETHSM_SYSTEM_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TLS_CRT=
TLS_KEY=

POSTGRES_USER=admin
POSTGRES_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)
RABBIT_USER=admin
RABBIT_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)

KEYCLOAK_USER=admin
KEYCLOAK_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)
SAMPLE_DATA_CLIENT_SECRET=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} | tr -d '\n'
    echo
)

function main() {
    init

    process_flags "$@"

    detect_distribution
    if [ "$KUBE_CONTEXT" != "" ]; then
        # Explicit context must take precedence over local microk8s auto-detection.
        dist="kubectl"
        KUBECTL_CONTEXT_ARGS=(--context "$KUBE_CONTEXT")
        HELM_CONTEXT_ARGS=(--kube-context "$KUBE_CONTEXT")
    elif [ "$dist" == "microk8s" ]; then
        kube="microk8s"
    fi

    echo -e "${BLUE}=== Installing Lamassu IoT using Fast Lane ===${NOCOLOR}"
    echo -e "\n${BLUE}1) Dependencies checking${NOCOLOR}"
    check_dependencies
    echo -e "\n${BLUE}2) Provide minimal config info${NOCOLOR}"
    request_config_data
    if [ "$WITH_HSM" = true ]; then
        detect_nethsm_support
        echo -e "\n${BLUE}2.1) Prepare SoftHSM SSH credentials${NOCOLOR}"
        prepare_softhsm_ssh_keypair
    fi
    echo -e "\n${BLUE}3) Create ${NAMESPACE} namespace${NOCOLOR}"
    create_kubernetes_namespace
    STEP_START_TIME=$(date +%s)
    echo -e "\n${BLUE}4) Install PostgreSQL${NOCOLOR}"
    install_postgresql
    checkpoint "PostgreSQL"
    echo -e "\n${BLUE}5) Install Auth - Keycloak${NOCOLOR}"
    install_keycloak
    checkpoint "Keycloak"
    echo -e "\n${BLUE}6) Install RabbitMQ${NOCOLOR}"
    install_rabbitmq
    checkpoint "RabbitMQ"

    next_step=7
    if [ "$OTEL" = true ]; then
        echo -e "\n${BLUE}${next_step}) Install Observability Stack (Victoria Logs + VictoriaTraces + Jaeger + OTel Collector)${NOCOLOR}"
        install_observability
        checkpoint "Observability Stack"
        next_step=$((next_step + 1))
    fi

    if [ "$WITH_HSM" = true ]; then
        echo -e "\n${BLUE}${next_step}) Install SoftHSM${NOCOLOR}"
        install_softhsm
        checkpoint "SoftHSM"
        next_step=$((next_step + 1))
    fi

    echo -e "\n${BLUE}${next_step}) Install Lamassu IoT. It may take a few minutes${NOCOLOR}"
    install_lamassu
    checkpoint "Lamassu IoT"

    if [ "$SAMPLE_DATA" = true ]; then
        echo -e "\n${BLUE}9) Populate sample data${NOCOLOR}"
        populate_sample_data
    fi

    final_instructions
}

function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo " -h, --help                   Display this help message"
    echo " -c, --context                Kubernetes context to use (kubectl/helm)"
    echo " -n, --non-interactive        Enable non-interactive mode. Credentials for Keycloak, Postgres and RabbitMQ will be auto generated"
    echo " -ns, --namespace             Kubernetes Namespace where LAMASSU will be deployed"
    echo " -d, --domain                 Domain to be set while deploying LAMASSU"
    echo " -v, --version                Version of the Lamassu Helm Chart to be installed. Default is latest"
    echo " --https-port                 HTTPS port to be used for Lamassu IoT. Default is 443"
    echo " --http-port                  HTTP port to be used for Lamassu IoT. Default is 80"
    echo " --tls-crt                    Path to the PEM encoded certificate used for downstream communications"
    echo " --tls-key                    Path to the PEM encoded key used for downstream communications"
    echo " -l, --local-chart-path       Path to the local chart folder"
    echo " -ip, --gateway-ip            IP address to set as the Envoy Gateway address (overrides auto-detected host IPs)"
    echo " --otel                       Deploy Victoria Logs, VictoriaTraces, Jaeger & an OTel Collector (fan-out) and configure OpenTelemetry in all Lamassu services"
    echo " --sample-data                Populate Lamassu with sample data (CAs, profiles, certificates, DMS, devices) after installation"
    echo " --softhsm-chart-path         Path to the local SoftHSM chart folder. Default: charts/softhsm in this repository"
    echo " --with-hsm                   Install SoftHSM and NetHSM, and configure Lamassu KMS to use PKCS#11 (NetHSM is skipped on ARM clusters, amd64-only image)"
}

function has_argument() {
    [[ ("$1" == *=* && -n ${1#*=}) || ( ! -z "$2" && "$2" != -*)  ]];
}

function extract_argument() {
  echo "${2:-${1#*=}}"
}

function process_flags() {
    while [ $# -gt 0 ]; do
        case $1 in
        -h | --help)
            usage
            exit 0
            ;;
        -c | --context*)
            if ! has_argument $@; then
                echo -e "\n${RED}Context not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            KUBE_CONTEXT=$(extract_argument $@)

            shift
            ;;
        --with-hsm)
            WITH_HSM=true
            ;;
        --softhsm-chart-path)
            if ! has_argument $@; then
                echo -e "\n${RED}SoftHSM chart path not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            SOFTHSM_CHART_PATH=$(extract_argument $@)

            shift
            ;;
         --tls-crt)
              if ! has_argument $@; then
                echo -e "\n${RED}TLS Certificate not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            TLS_CRT=$(extract_argument $@)

            shift
            ;;
         --tls-key)
              if ! has_argument $@; then
                echo -e "\n${RED}TLS Key not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            TLS_KEY=$(extract_argument $@)

            shift
            ;;
        -n | --non-interactive)
            NON_INTERACTIVE=true
            ;;
        -d | --domain*)
            if ! has_argument $@; then
                  echo -e "\n${RED}Domain not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            DOMAIN_OVERRIDE=true
            DOMAIN=$(extract_argument $@)

            shift
            ;;

        --https-port)
            if ! has_argument $@; then
                  echo -e "\n${RED}HTTPS port not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            HTTPS_PORT=$(extract_argument $@)

            shift
            ;;

        --http-port)
            if ! has_argument $@; then
                  echo -e "\n${RED}HTTP port not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            HTTP_PORT=$(extract_argument $@)

            shift
            ;;

        -ns | --namespace*)
            if ! has_argument $@; then
            echo -e "\n${RED}Namespace not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            NAMESPACE_OVERRIDE=true
            NAMESPACE=$(extract_argument $@)

            shift
            ;;
        -v | --version*)
            if ! has_argument $@; then
            echo -e "\n${RED}Version not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            VERSION_OVERRIDE=true
            VERSION=$(extract_argument $@)

            shift
            ;;
        -l | --local-chart-path*)
            if ! has_argument $@; then
            echo -e "\n${RED}Path not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            LAMASSU_USE_LOCAL_PATH=true
            LAMASSU_CHART_PATH=$(extract_argument $@)

            shift
            ;;
        -ip | --gateway-ip*)
            if ! has_argument $@; then
                echo -e "\n${RED}Gateway IP not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            GATEWAY_IP=$(extract_argument $@)

            shift
            ;;
        --otel)
            OTEL=true
            ;;
        --sample-data)
            SAMPLE_DATA=true
            ;;
        *)
            echo -e "\n${RED}Invalid option: $1${NOCOLOR}" >&2
            usage
            exit 1
            ;;
        esac
        shift
    done
}

function final_instructions() {
    echo -e "${GREEN}=== Lamassu IoT has been installed in your Kubernetes instance ===${NOCOLOR}"
    echo -e "${GREEN}Total installation time: $(format_duration $(($(date +%s) - SCRIPT_START_TIME)))${NOCOLOR}"
    echo -e "${BLUE}Please connect to https://${DOMAIN} using default user lamassu/lamassu ${NOCOLOR}"
    echo -e "${BLUE}You will be required to change the password on the first connection${NOCOLOR}"
    echo -e "${BLUE}If more users are needed connect to  https://${DOMAIN}/auth/admin${NOCOLOR}"
    echo -e "${BLUE}Use the provided Keycloak credentials ${KEYCLOAK_USER}/${KEYCLOAK_PWD}${NOCOLOR}"
    if [ "$WITH_HSM" = true ]; then
                echo -e "${BLUE}SoftHSM endpoint configured for PKCS#11 via p11-kit socket forwarding${NOCOLOR}"
    fi
}

function prepare_softhsm_ssh_keypair() {
        if [ -n "$SOFTHSM_SSH_PUBLIC_KEY" ] && [ -n "$SOFTHSM_SSH_PRIVATE_KEY_FILE" ]; then
                return 0
        fi

        local key_dir
        key_dir=$(mktemp -d /tmp/lamassu-kms-pkcs11-XXXXXX)
        SOFTHSM_SSH_PRIVATE_KEY_FILE="$key_dir/ssh-key"
        ssh-keygen -q -t ed25519 -N "" -f "$SOFTHSM_SSH_PRIVATE_KEY_FILE" -C "lamassu-fastlane-pkcs11" >/dev/null
        SOFTHSM_SSH_PUBLIC_KEY=$(cat "$SOFTHSM_SSH_PRIVATE_KEY_FILE.pub")
}

function create_softhsm_kms_override_file() {
target_file="$1"

sidecar_image="ghcr.io/lamassuiot/p11-kit-ssh-sidecar:ci-test"
sidecar_pull_policy="Always"
nethsm_module_image="curlimages/curl:8.11.0"
nethsm_module_pull_policy="IfNotPresent"
# Must match the SoftHSM base image: p11-kit client and server versions must
# be RPC-compatible (see ci/softhsm/dockerfile).
p11kit_module_image="ubuntu:26.04"
p11kit_module_pull_policy="IfNotPresent"

cat >"$target_file" <<EOF
services:
  kms:
    pkcs11Sidecar:
      enabled: true
      image: ${sidecar_image}
      imagePullPolicy: ${sidecar_pull_policy}
      socketDir: /run/p11-kit
      env:
        - name: SSH_DESTINATION
          value: root@hsm-softhsm
        - name: SSH_IDENTITY_FILE
          value: /etc/p11-kit-ssh/.key
        - name: P11_LOCAL_SOCKET
          value: /run/p11-kit/pkcs11
        - name: P11_REMOTE_SOCKET
          value: /run/p11-kit/pkcs11
      volumeMounts:
        - name: kms-pkcs11-ssh-key
          mountPath: /etc/p11-kit-ssh
          readOnly: true
      volumes:
        - name: kms-pkcs11-ssh-key
          secret:
            secretName: kms-pkcs11-sidecar-ssh-key
EOF

cat >>"$target_file" <<EOF
    pkcs11Modules:
EOF

if [ "$WITH_NETHSM" = true ]; then
# NetHSM engine: stage libnethsm_pkcs11.so and its config in a shared volume.
cat >>"$target_file" <<EOF
      - name: nethsm
        image: ${nethsm_module_image}
        imagePullPolicy: ${nethsm_module_pull_policy}
        mountPath: /run/nethsm
        command:
          - /bin/sh
          - -ec
          - |
EOF

cat >>"$target_file" <<'EOF'
            set -eu
            TARGET_DIR="${PKCS11_MODULE_DIR:-/run/nethsm}"
            mkdir -p "${TARGET_DIR}"
            case "$(uname -m)" in
              x86_64) ARCH=x86_64 ;;
              aarch64|arm64) ARCH=aarch64 ;;
              *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
            esac
            URL="https://github.com/Nitrokey/nethsm-pkcs11/releases/download/${NETHSM_PKCS11_VERSION}/nethsm-pkcs11-${NETHSM_PKCS11_VERSION}-${ARCH}-linux-glibc.so"
            echo "Downloading ${URL}"
            curl -fsSL "${URL}" -o "${TARGET_DIR}/libnethsm_pkcs11.so"
            chmod 0555 "${TARGET_DIR}/libnethsm_pkcs11.so"
            cat > "${TARGET_DIR}/p11nethsm.yaml" <<CFG
            log_level: ${NETHSM_LOG_LEVEL:-Info}
            slots:
              - label: ${NETHSM_SLOT_LABEL:-LocalHSM}
                operator:
                  username: "${NETHSM_OPERATOR_USER:-operator}"
                  password: "${NETHSM_OPERATOR_PASSWORD:-}"
                administrator:
                  username: "${NETHSM_ADMIN_USER:-admin}"
                  password: "${NETHSM_ADMIN_PASSWORD:-}"
                instances:
                  - url: "${NETHSM_URL:-https://hsm-nethsm:8443/api/v1}"
                    danger_insecure_cert: ${NETHSM_INSECURE_CERT:-true}
                retries:
                  count: 3
                  delay_seconds: 1
                timeout_seconds: 10
            CFG
            chmod 0444 "${TARGET_DIR}/p11nethsm.yaml"
            ls -l "${TARGET_DIR}"
EOF

cat >>"$target_file" <<EOF
        env:
          - name: NETHSM_PKCS11_VERSION
            value: "${NETHSM_PKCS11_VERSION}"
          - name: NETHSM_URL
            value: https://hsm-nethsm:8443/api/v1
          - name: NETHSM_SLOT_LABEL
            value: ${NETHSM_TOKEN_LABEL}
          - name: NETHSM_OPERATOR_USER
            value: operator
          - name: NETHSM_OPERATOR_PASSWORD
            valueFrom:
              secretKeyRef:
                name: hsm-nethsm-provision
                key: operatorPassphrase
          - name: NETHSM_ADMIN_USER
            value: admin
          - name: NETHSM_ADMIN_PASSWORD
            valueFrom:
              secretKeyRef:
                name: hsm-nethsm-provision
                key: adminPassphrase
EOF
fi

# SoftHSM engine: stage p11-kit-client.so and its non-core dependencies.
cat >>"$target_file" <<EOF
      - name: p11-kit-client
        image: ${p11kit_module_image}
        imagePullPolicy: ${p11kit_module_pull_policy}
        mountPath: /run/p11-kit-modules
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: false
          runAsUser: 0
          runAsGroup: 0
          capabilities:
            drop:
              - ALL
            add:
              - CHOWN
              - DAC_OVERRIDE
              - FOWNER
              - SETGID
              - SETUID
        command:
          - /bin/sh
          - -ec
          - |
EOF

cat >>"$target_file" <<'EOF'
            set -eu
            TARGET_DIR="${PKCS11_MODULE_DIR:-/run/p11-kit-modules}"
            mkdir -p "${TARGET_DIR}"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y --no-install-recommends p11-kit-modules
            MOD="$(dpkg -L p11-kit-modules | grep -m1 '/p11-kit-client\.so$')"
            [ -n "${MOD}" ] || { echo "p11-kit-client.so not found" >&2; exit 1; }
            echo "Staging ${MOD} -> ${TARGET_DIR}/p11-kit-client.so"
            cp -L "${MOD}" "${TARGET_DIR}/p11-kit-client.so"
            ldd "${MOD}" | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p' | while read -r lib; do
              case "${lib}" in
                */libc.so*|*/libm.so*|*/libpthread.so*|*/libdl.so*|*/librt.so*|*/ld-linux*) continue ;;
              esac
              cp -L "${lib}" "${TARGET_DIR}/" 2>/dev/null || true
            done
            chmod -R 0555 "${TARGET_DIR}"
            ls -l "${TARGET_DIR}"
EOF

cat >>"$target_file" <<EOF
    cryptoEngines:
      defaultEngineID: "pkcs11-softhsm"
      engines:
        - id: "pkcs11-softhsm"
          type: "pkcs11"
          token: "${SOFTHSM_LABEL}"
          pin: "${SOFTHSM_PIN}"
          module_path: "/run/p11-kit-modules/p11-kit-client.so"
          module_extra_options:
            env:
              P11_KIT_SERVER_ADDRESS: "unix:path=/run/p11-kit/pkcs11"
              LD_LIBRARY_PATH: "/run/p11-kit-modules"
EOF

if [ "$WITH_NETHSM" = true ]; then
cat >>"$target_file" <<EOF
        - id: "pkcs11-nethsm"
          type: "pkcs11"
          token: "${NETHSM_TOKEN_LABEL}"
          pin: "${NETHSM_OPERATOR_PASSPHRASE}"
          module_path: "/run/nethsm/libnethsm_pkcs11.so"
          module_extra_options:
            env:
              P11NETHSM_CONFIG_FILE: "/run/nethsm/p11nethsm.yaml"
EOF
fi

cat >>"$target_file" <<EOF
        - id: "filesystem-1"
          type: "filesystem"
          storage_directory: "/crypto/fs"
EOF
}


function install_lamassu() {
if [ "$HTTPS_PORT" -ne 443 ]; then
    DOMAIN="$DOMAIN:$HTTPS_PORT"
fi

    cat >lamassu.yaml <<"EOF"
postgres:
  hostname: "postgresql"
  port: 5432
  username: ""
  password: ""

amqp:
  hostname: "rabbitmq"
  port: 5672
  username: ""
  password: ""
  tls: false

services:
  ca:
    cryptoEngines:
      defaultEngineID: fs-1
      engines:
      - id: fs-1
        type: filesystem
        storage_directory: /crypto/fs
  authz:
    credentials:
      pki:
        database: pki
        hostname: "postgresql"
        port: 5432
        username: ""
        password: ""
      authz:  
        database: authz
        hostname: "postgresql"
        port: 5432
        username: ""
        password: ""
    bootstrap:
    - principal_id: "oidc:lamassu"
      principal_name: "lamassu"
      principal_type: "oidc"
      policy_ids:
        - "lamassu.a6811b60-5f89-4ce7-badb-78ea234794d3"
      auth_config:
        claims:
          - claim: "preferred_username"
            operator: "equals"
            value: "lamassu"
    jwkUrl: http://auth-keycloak/auth/realms/lamassu/protocol/openid-connect/certs

gateway:
  extraRouting:
  - path: /auth
    name: auth
    target:
      host: auth-keycloak
      port: 80 # If no sidecar is used
EOF

export DOMAIN=$DOMAIN
yq -i '.services.ca.domains = [env(DOMAIN)]' lamassu.yaml

if [ "$SAMPLE_DATA" = true ]; then
    # Keycloak's service-account username for the "sample-data" client is
    # "service-account-sample-data", not "lamassu", so it needs its own authz
    # bootstrap principal alongside the human "lamassu" user's.
    yq -i '.services.authz.bootstrap += [{
        "principal_id": "oidc:service-account-sample-data",
        "principal_name": "service-account-sample-data",
        "principal_type": "oidc",
        "policy_ids": ["lamassu.a6811b60-5f89-4ce7-badb-78ea234794d3"],
        "auth_config": {
            "claims": [
                {"claim": "preferred_username", "operator": "equals", "value": "service-account-sample-data"}
            ]
        }
    }]' lamassu.yaml
fi

if [ -n "$GATEWAY_IP" ]; then
    export IP_LIST="$GATEWAY_IP"
else
    export IP_LIST="$(hostname -I)"
fi
export HTTPS_PORT=$HTTPS_PORT
export HTTP_PORT=$HTTP_PORT

yq -i '.gateway.addresses = (env(IP_LIST) | split(" "))' lamassu.yaml
yq -i '.gateway.ports.https = env(HTTPS_PORT)' lamassu.yaml
yq -i '.gateway.ports.http = env(HTTP_PORT)' lamassu.yaml

# Check if TLS_CRT and TLS_KEY are not empty
if [[ -n "$TLS_CRT" && -n "$TLS_KEY" ]]; then
    echo -e "${ORANGE}Deploying Lamassu with EXTERNAL TLS Certificates${NOCOLOR}"

    run_kubectl create secret tls downstream-provided-crt --cert=$TLS_CRT --key=$TLS_KEY -n $NAMESPACE

    cat >tls.yaml <<"EOF"
tls:
  type: external
  externalOptions:
    secretName: downstream-provided-crt
EOF

    yq eval-all '. as $item ireduce ({}; . * $item )' lamassu.yaml tls.yaml -i
    rm tls.yaml
else
    echo -e "${ORANGE}Deploying Lamassu with SelfSigned TLS Certificates${NOCOLOR}"
    yq -i '.tls.type = "certManager"' lamassu.yaml
    yq -i '.tls.certManagerOptions.issuer = ""' lamassu.yaml
    yq -i '.tls.certManagerOptions.certSpec.commonName = (env(DOMAIN))' lamassu.yaml
    yq -i '.tls.certManagerOptions.certSpec.addresses = (env(IP_LIST) | split(" "))' lamassu.yaml
fi

if [ "$WITH_HSM" = true ]; then
    if [ -z "$SOFTHSM_SSH_PRIVATE_KEY_FILE" ]; then
        echo -e "\n${RED}SoftHSM SSH private key is not prepared.${NOCOLOR}"
        exit 1
    fi
    run_kubectl create secret generic kms-pkcs11-sidecar-ssh-key \
        --from-file=.key="$SOFTHSM_SSH_PRIVATE_KEY_FILE" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | run_kubectl apply -f -
    create_softhsm_kms_override_file softhsm-kms.yaml
    yq eval-all '. as $item ireduce ({}; . * $item )' lamassu.yaml softhsm-kms.yaml -i
    rm softhsm-kms.yaml
fi

    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    export RABBIT_USER=$RABBIT_USER
    export RABBIT_PWD=$RABBIT_PWD

    yq -i '.postgres.username = (env(POSTGRES_USER))' lamassu.yaml
    yq -i '.postgres.password = (env(POSTGRES_PWD))' lamassu.yaml
    yq -i '.services.authz.credentials.pki.username = (env(POSTGRES_USER))' lamassu.yaml
    yq -i '.services.authz.credentials.pki.password = (env(POSTGRES_PWD))' lamassu.yaml
    yq -i '.services.authz.credentials.authz.username = (env(POSTGRES_USER))' lamassu.yaml
    yq -i '.services.authz.credentials.authz.password = (env(POSTGRES_PWD))' lamassu.yaml

    yq -i '.amqp.username = (env(RABBIT_USER))' lamassu.yaml
    yq -i '.amqp.password = (env(RABBIT_PWD))' lamassu.yaml

    if [ "$OTEL" = true ]; then
        yq -i '.observability.enabled = true' lamassu.yaml
    fi

    helm_path=$LAMASSU_CHART_PATH
    if [ "$LAMASSU_USE_LOCAL_PATH" = false ]; then
        run_helm repo add lamassuiot http://www.lamassu.io/lamassu-helm/
    else
        echo -e "${ORANGE}Using local chart path ${LAMASSU_CHART_PATH} ${NOCOLOR}"
    fi

    helm_version=""
    if [ "$VERSION_OVERRIDE" = true ]; then
        helm_version="--version $VERSION"
    fi

    run_helm install -n $NAMESPACE lamassu $helm_path $helm_version -f lamassu.yaml --wait --timeout "$HELM_INSTALL_TIMEOUT"

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Lamassu IoT installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing Lamassu IoT${NOCOLOR}"
        exit 1
    fi
}

function populate_sample_data() {
    SERVER="https://${DOMAIN}" \
    INSECURE_SKIP_VERIFY=true \
    OIDC_WELL_KNOWN_URL="https://${DOMAIN}/auth/realms/lamassu/.well-known/openid-configuration" \
    OIDC_CLIENT_ID=sample-data \
    OIDC_CLIENT_SECRET="${SAMPLE_DATA_CLIENT_SECRET}" \
    "${SCRIPT_DIR}/sample-data.sh"
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Sample data populated${NOCOLOR}"
    else
        echo -e "\n${RED}Error populating sample data${NOCOLOR}"
        exit 1
    fi
}

function install_rabbitmq() {
    cat >rabbitmq.yaml <<"EOF"
fullnameOverride: "rabbitmq"

image:
  registry: docker.io
  repository: rabbitmq
  tag: "4.3.0"

auth:
  username:
  password:
EOF

   export RABBIT_USER=$RABBIT_USER
   export RABBIT_PWD=$RABBIT_PWD

   yq -i '.auth.username = env(RABBIT_USER)' rabbitmq.yaml
   yq -i '.auth.password = env(RABBIT_PWD)' rabbitmq.yaml

    helm_path=oci://registry-1.docker.io/cloudpirates/rabbitmq

    run_helm install rabbitmq $helm_path --version 0.21.4 -n $NAMESPACE -f rabbitmq.yaml --wait --timeout "$HELM_INSTALL_TIMEOUT"
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}RabbitMQ installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing RabbitMQ${NOCOLOR}"
        exit 1
    fi
}

function install_keycloak() {
    cat >keycloak.yaml <<"EOF"
image:
  registry: docker.io
  repository: keycloak/keycloak
  tag: "26.6.2"

service:
  httpPort: 80

keycloak:
  adminUser: ""
  adminPassword: ""
  httpRelativePath: /auth
  proxyHeaders: xforwarded

database:
  type: postgres
  host: "postgresql"
  port: "5432"
  name: "auth"
  username: ""
  password: ""

postgres:
  enabled: false

mariadb:
  enabled: false

extraEnvVars:
  - name: KC_HOSTNAME_STRICT
    value: "false"
  - name: KC_HEALTH_ENABLED
    value: "true"
  - name: KC_SPI_X509CERT_LOOKUP_PROVIDER
    value: "envoy"
  - name: HTTP_ADDRESS_FORWARDING
    value: "true"
  - name: KC_HTTP_ACCESS_LOG_ENABLED
    value: "true"
  - name: KC_HTTP_ACCESS_LOG_PATTERN
    value: combined

realm:
  import: true
  configFile: |
    {
      "realm": "lamassu",
      "enabled": true,
      "loginTheme": "lamassu-theme-v3",
      "roles": {
        "realm": [
          {
            "name": "pki-admin",
            "description": "PKI Full Access"
          }
        ]
      },
      "users": [
        {
          "username": "lamassu",
          "enabled": true,
          "credentials": [
            {
              "type": "password",
              "value": "lamassu",
              "temporary": true
            }
          ],
          "requiredActions": ["UPDATE_PASSWORD"],
          "realmRoles": ["pki-admin"]
        }
      ],
      "clients": [
        {
          "clientId": "frontend",
          "enabled": true,
          "redirectUris": ["/*"],
          "webOrigins": ["/*"],
          "publicClient": true,
          "directAccessGrantsEnabled": true
        }
      ]
    }
EOF

    if [ "$SAMPLE_DATA" = true ]; then
        local realm_config
        if ! realm_config=$(yq -r '.realm.configFile' keycloak.yaml | jq --arg secret "$SAMPLE_DATA_CLIENT_SECRET" '
            .users += [{
                username: "service-account-sample-data",
                enabled: true,
                serviceAccountClientId: "sample-data",
                realmRoles: ["pki-admin"]
            }] |
            .clients += [{
                clientId: "sample-data",
                enabled: true,
                protocol: "openid-connect",
                publicClient: false,
                clientAuthenticatorType: "client-secret",
                secret: $secret,
                serviceAccountsEnabled: true,
                standardFlowEnabled: false,
                directAccessGrantsEnabled: false,
                fullScopeAllowed: true
            }]
        '); then
            echo -e "\n${RED}Error configuring the Keycloak sample-data service account${NOCOLOR}"
            exit 1
        fi

        export SAMPLE_DATA_REALM_CONFIG="$realm_config"
        if ! yq -i '.realm.configFile = strenv(SAMPLE_DATA_REALM_CONFIG)' keycloak.yaml; then
            echo -e "\n${RED}Error writing the Keycloak sample-data service account configuration${NOCOLOR}"
            exit 1
        fi
        unset SAMPLE_DATA_REALM_CONFIG
    fi

    cat >>keycloak.yaml <<"EOF"
extraInitContainers:
- name: init-custom-theme
  image: curlimages/curl:8.10.1
  command:
  - 'sh'
  - '-c'
  - |
    curl -L -f -o /opt/keycloak/providers/lamassu-theme.jar https://github.com/lamassuiot/keycloak-theme/releases/download/3.0.0/lamassu-theme.jar
  volumeMounts:
  - mountPath: "/opt/keycloak/providers"
    name: keycloak-providers
EOF

    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    yq -i '.database.username = env(POSTGRES_USER)' keycloak.yaml
    yq -i '.database.password = env(POSTGRES_PWD)' keycloak.yaml

    export KEYCLOAK_USER=$KEYCLOAK_USER
    export KEYCLOAK_PWD=$KEYCLOAK_PWD
    yq -i '.keycloak.adminUser = env(KEYCLOAK_USER)' keycloak.yaml
    yq -i '.keycloak.adminPassword = env(KEYCLOAK_PWD)' keycloak.yaml


    helm_path=oci://registry-1.docker.io/cloudpirates/keycloak

    run_helm install auth $helm_path --version 0.21.9 -n $NAMESPACE --wait --timeout "$HELM_INSTALL_TIMEOUT" -f keycloak.yaml
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Keycloak installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing Keycloak${NOCOLOR}"
        exit 1
    fi
}

function install_postgresql() {
    cat >postgres.yaml <<"EOF"
fullnameOverride: "postgresql"
image:
  registry: docker.io
  repository: postgres
  tag: "18.4"
auth:
  username: ""
  password: ""
initdb:
  scripts:
    init.sql: |
      CREATE DATABASE auth;
      CREATE DATABASE pki;
      CREATE DATABASE authz;
      CREATE DATABASE wfx;

      \connect pki

      CREATE SCHEMA IF NOT EXISTS alerts;
      CREATE SCHEMA IF NOT EXISTS ca;
      CREATE SCHEMA IF NOT EXISTS va;
      CREATE SCHEMA IF NOT EXISTS devicemanager;
      CREATE SCHEMA IF NOT EXISTS dmsmanager;
      CREATE SCHEMA IF NOT EXISTS kms;
EOF

    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    yq -i '.auth.username = env(POSTGRES_USER)' postgres.yaml
    yq -i '.auth.password = env(POSTGRES_PWD)' postgres.yaml

    helm_path=oci://registry-1.docker.io/cloudpirates/postgres

    run_helm install postgres $helm_path -n $NAMESPACE --version 0.19.5 -f postgres.yaml --wait --timeout "$HELM_INSTALL_TIMEOUT"
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}PostgreSQL installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing PostgreSQL${NOCOLOR}"
        exit 1
    fi
}

function create_kubernetes_namespace() {
    # Check if the namespace exists
    if run_kubectl get ns "$NAMESPACE" &> /dev/null; then
        echo -e "\n${GREEN}Namespace $NAMESPACE already exists${NOCOLOR}"
    else
        # If the namespace doesn't exist, create it
        run_kubectl create ns $NAMESPACE
        echo "Namespace $NAMESPACE created."
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}Namespace $NAMESPACE created${NOCOLOR}"
        else
            echo -e "\n${RED}Error creating namespace $NAMESPACE${NOCOLOR}"
            exit 1
        fi
    fi
}

function install_softhsm() {
    if [ -z "$SOFTHSM_SSH_PUBLIC_KEY" ]; then
        echo -e "\n${RED}SoftHSM SSH public key is not prepared.${NOCOLOR}"
        exit 1
    fi

    helm_path="$SOFTHSM_CHART_PATH"

    run_helm install hsm "$helm_path" -n "$NAMESPACE" \
        --set-string ssh.authorizedKeys="$SOFTHSM_SSH_PUBLIC_KEY" \
        --set-string softhsm.label="$SOFTHSM_LABEL" \
        --set-string softhsm.pin="$SOFTHSM_PIN" \
        --set-string softhsm.slot="$SOFTHSM_SLOT" \
        --set-string softhsm.so_pin="$SOFTHSM_SO_PIN" \
        --set nethsm.enabled=$WITH_NETHSM \
        --set-string nethsm.tokenLabel="$NETHSM_TOKEN_LABEL" \
        --set-string nethsm.provision.unlockPassphrase="$NETHSM_UNLOCK_PASSPHRASE" \
        --set-string nethsm.provision.adminPassphrase="$NETHSM_ADMIN_PASSPHRASE" \
        --set-string nethsm.provision.systemTime="$NETHSM_SYSTEM_TIME" \
        --set-string nethsm.provision.operator.passphrase="$NETHSM_OPERATOR_PASSPHRASE" \
        --wait
    if [ $? -eq 0 ]; then
        if [ "$WITH_NETHSM" = true ]; then
            echo -e "\n${GREEN}SoftHSM installed${NOCOLOR}"
        else
            echo -e "\n${GREEN}SoftHSM installed (NetHSM skipped)${NOCOLOR}"
        fi
    else
        echo -e "\n${RED}Error installing SoftHSM${NOCOLOR}"
        exit 1
    fi
}

function request_config_data() {
    if [ "$NON_INTERACTIVE" = false ]; then
        request_domain
        request_postgres_user
        request_postgres_pwd
        request_rabbit_user
        request_rabbit_pwd
        request_keycloak_user
        request_keycloak_pwd
        request_namespace
    else
        echo -e "${ORANGE}Non-interactive mode enabled. Credentials will be auto generated${NOCOLOR}"
        if [ "$DOMAIN_OVERRIDE" = false ]; then
            echo -e "${ORANGE}Domain not provied. Default will be used: $DOMAIN${NOCOLOR}"
        fi
        if [ "$NAMESPACE_OVERRIDE" = false ]; then
            echo -e "${ORANGE}Namespace not provied. Default will be used: $NAMESPACE${NOCOLOR}"
        fi
    fi
}

function request_domain() {
    echo -n "Lamassu IoT Domain ($DOMAIN): "
    read reqdomain
    if [ "$reqdomain" != "" ]; then
        DOMAIN=$reqdomain
    fi
}

function request_postgres_user() {
    echo -n "PostgreSQL admin user ($POSTGRES_USER): "
    read req
    if [ "$req" != "" ]; then
        POSTGRES_USER=$req
    fi
}

function request_postgres_pwd() {
    echo -n "PostgreSQL admin password ($POSTGRES_PWD): "
    read req
    if [ "$req" != "" ]; then
        POSTGRES_PWD=$req
    fi
}

function request_rabbit_user() {
    echo -n "RabbitMQ admin user ($RABBIT_USER): "
    read req
    if [ "$req" != "" ]; then
        RABBIT_USER=$req
    fi
}

function request_rabbit_pwd() {
    echo -n "RabbitMQ admin password ($RABBIT_PWD): "
    read req
    if [ "$req" != "" ]; then
        RABBIT_PWD=$req
    fi
}

function request_keycloak_user() {
    echo -n "Keycloak admin user ($KEYCLOAK_USER): "
    read req
    if [ "$req" != "" ]; then
        KEYCLOAK_USER=$req
    fi
}

function request_keycloak_pwd() {
    echo -n "Keycloak admin password ($KEYCLOAK_PWD): "
    read req
    if [ "$req" != "" ]; then
        KEYCLOAK_PWD=$req
    fi
}

function request_namespace() {
    echo -n "Kubernetes namespace ($NAMESPACE): "

    read req
    if [ "$req" != "" ]; then
        NAMESPACE=$req
    fi
}

function detect_distribution() {
    is_command_installed "microk8s"
    if [ $? -eq 0 ]; then
        dist="microk8s"
        echo -e "${GREEN}Microk8s detected${NOCOLOR}"
        return 0
    fi
    is_command_installed "k3s"
    if [ $? -eq 0 ]; then
        dist="k3s"
        echo -e "${GREEN}K3s detected${NOCOLOR}"
        return 0
    fi
    is_command_installed "kind"
    if [ $? -eq 0 ]; then
        dist="kind"
        echo -e "${GREEN}Kind detected - USE IT ONLY FOR TESTING${NOCOLOR}"
        return 0
    fi

    is_command_installed "kubectl"
    if [ $? -eq 0 ]; then
        dist="kubectl"
        echo -e "${GREEN}kubectl detected (using kubeconfig context)${NOCOLOR}"
        return 0
    fi

    echo -e "${RED}No kubernetes distribution found (microk8s, k3s, kind) and kubectl is not installed${NOCOLOR}"
    exit 1
}

function check_dependencies() {
    exit_if_command_not_installed yq
    if [ "$SAMPLE_DATA" = true ]; then
        exit_if_command_not_installed jq
    fi
    if [ $dist == "microk8s" ]; then
        exit_if_command_not_installed $dist
    else
        exit_if_command_not_installed kubectl
        exit_if_command_not_installed helm

        if [ "$KUBE_CONTEXT" != "" ]; then
            if kubectl config get-contexts -o name | grep -Fxq "$KUBE_CONTEXT"; then
                echo "✅ context $KUBE_CONTEXT"
            else
                echo "Context '$KUBE_CONTEXT' not found in kubeconfig. Exiting"
                exit 1
            fi
        fi
    fi

    if [ "$WITH_HSM" = true ]; then
        exit_if_command_not_installed ssh-keygen
    fi

    if [ $dist == "microk8s" ]; then
        exit_if_kube_command_not_installed kubectl
        exit_if_kube_command_not_installed helm
        check_microk8s_minimum_requirements
    else
        check_envoy_gateway_helm
    fi

}

function detect_nethsm_support() {
    local node_arches
    local node_arch
    local has_amd64=false
    local has_arm64=false

    if ! node_arches=$(run_kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.architecture}{"\n"}{end}' 2>/dev/null) || [ -z "$node_arches" ]; then
        echo -e "${ORANGE}Unable to determine Kubernetes node architectures; skipping NetHSM. SoftHSM/PKCS#11 will still be installed.${NOCOLOR}" >&2
        WITH_NETHSM=false
        return 0
    fi

    while IFS=$'\t' read -r _ node_arch; do
        case "$node_arch" in
            amd64)
                has_amd64=true
                ;;
            arm64 | aarch64)
                has_arm64=true
                ;;
            *)
                echo -e "${ORANGE}Unsupported or missing Kubernetes node architecture: ${node_arch:-unknown}; skipping NetHSM. SoftHSM/PKCS#11 will still be installed.${NOCOLOR}" >&2
                WITH_NETHSM=false
                return 0
                ;;
        esac
    done <<< "$node_arches"

    if [ "$has_amd64" = false ]; then
        WITH_NETHSM=false
        if [ "$has_arm64" = true ]; then
            echo -e "${ORANGE}ARM Kubernetes cluster detected: NetHSM has no ARM image, skipping its deployment. SoftHSM/PKCS#11 will still be installed.${NOCOLOR}"
        else
            echo -e "${ORANGE}No amd64 Kubernetes node detected: skipping NetHSM deployment. SoftHSM/PKCS#11 will still be installed.${NOCOLOR}"
        fi
    elif [ "$has_arm64" = true ]; then
        echo -e "${ORANGE}Mixed-architecture cluster detected: NetHSM will be restricted to amd64 nodes.${NOCOLOR}"
    fi
}

function check_microk8s_minimum_requirements() {
    is_microk8s_addon_enabled helm
    is_microk8s_addon_enabled hostpath-storage
    is_microk8s_addon_enabled dns
    is_microk8s_addon_enabled cert-manager
    check_envoy_gateway_helm
}

function init() {
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    ORANGE='\033[0;33m'
    GREEN='\033[0;32m'
    NOCOLOR='\033[0m'

    SCRIPT_START_TIME=$(date +%s)
    STEP_START_TIME=$SCRIPT_START_TIME
}

function format_duration() {
    local total=$1
    local h=$((total / 3600))
    local m=$(((total % 3600) / 60))
    local s=$((total % 60))
    if [ "$h" -gt 0 ]; then
        printf '%dh %dm %ds' "$h" "$m" "$s"
    elif [ "$m" -gt 0 ]; then
        printf '%dm %ds' "$m" "$s"
    else
        printf '%ds' "$s"
    fi
}

function checkpoint() {
    local label="$1"
    local now
    now=$(date +%s)
    local step_elapsed=$((now - STEP_START_TIME))
    local total_elapsed=$((now - SCRIPT_START_TIME))
    echo -e "${GREEN}⏱  Checkpoint [${label}]: took $(format_duration "$step_elapsed") (total elapsed: $(format_duration "$total_elapsed"))${NOCOLOR}"
    STEP_START_TIME=$now
}

function run_kubectl() {
    if [ "$kube" == "microk8s" ]; then
        microk8s kubectl "${KUBECTL_CONTEXT_ARGS[@]}" "$@"
    else
        kubectl "${KUBECTL_CONTEXT_ARGS[@]}" "$@"
    fi
}

function run_helm() {
    if [ "$kube" == "microk8s" ]; then
        microk8s helm "${HELM_CONTEXT_ARGS[@]}" "$@"
    else
        helm "${HELM_CONTEXT_ARGS[@]}" "$@"
    fi
}

function is_command_installed() {
    if ! command -v "$1" &>/dev/null; then
        return 1
    else
        return 0
    fi
}

function exit_if_kube_command_not_installed() {
    if $kube $1 version &>/dev/null; then
        echo "✅ $1"
    else
        echo "$1: Addon not detected. Exiting"
        exit 1
    fi
}

function exit_if_command_not_installed() {
    is_command_installed "$1"
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "$1: Not detected. Exiting"
        exit 1
    fi
}

function is_microk8s_addon_enabled() {
    if [ $(microk8s status --a $1) == "enabled" ]; then
        echo "✅ $1 addon enabled"
    else
        echo "$1: Addon not enabled. Exiting"
        exit 1
    fi
}

function check_envoy_gateway_helm() {
    envoy_gateway_version="v1.8.0"
    # Versions shipped by gateway-crds-helm ${envoy_gateway_version}: Gateway API bundle
    # v1.5.1 (experimental) and Envoy Gateway CRDs generated by controller-gen
    # v0.20.x.
    local gateway_api_bundle_version="v1.5.1"
    local eg_kubebuilder_pinned_minor=20
    # Gateway API CRDs Lamassu needs: the chart renders Gateway and HTTPRoute, and
    # this script creates the eg GatewayClass.
    local gateway_api_required_crds="gatewayclasses.gateway.networking.k8s.io gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io"

    # render_gateway_crds <gateway_api:true|false> <envoy_gateway:true|false>: renders
    # the CRD bundle of the pinned release. Each half can be toggled so one can be
    # applied without touching the other.
    function render_gateway_crds() {
        run_helm template eg-crds oci://docker.io/envoyproxy/gateway-crds-helm \
            --version "${envoy_gateway_version}" \
            --set crds.gatewayAPI.enabled="$1" \
            --set crds.gatewayAPI.channel=experimental \
            --set crds.envoyGateway.enabled="$2"
    }

    # crd_present <crd>: returns 0 if the CRD exists, 1 if it does not. Any other
    # kubectl failure aborts: shared CRDs are never modified on a guess.
    function crd_present() {
        local out
        if ! out=$(run_kubectl get crd "$1" --ignore-not-found -o name 2>&1); then
            echo "❌ Could not query CRD $1: ${out}"
            echo "   Refusing to modify cluster-wide CRDs without knowing their state. Fix cluster access and rerun."
            exit 1
        fi
        [ -n "$out" ]
    }

    # crd_annotation <crd> <escaped jsonpath key>: prints the annotation value
    # (empty if unset). Aborts on kubectl failures.
    function crd_annotation() {
        local out
        if ! out=$(run_kubectl get crd "$1" -o jsonpath="{.metadata.annotations.$2}" 2>&1); then
            echo "❌ Could not read annotations of CRD $1: ${out}" >&2
            exit 1
        fi
        echo "$out"
    }

    # find_missing_crds <crd...>: sets missing_crds to the given CRDs absent from the
    # cluster (empty = all present).
    function find_missing_crds() {
        local crd
        missing_crds=""
        for crd in "$@"; do
            crd_present "$crd" || missing_crds+="${crd} "
        done
        missing_crds="${missing_crds% }"
    }

    # 1. CRDs first, controller second. CRDs are applied with kubectl (field
    # manager "kubectl"), so the eg Helm install below must skip its bundled
    # CRDs; otherwise its server-side apply conflicts with kubectl ownership
    # on the safe-upgrades ValidatingAdmissionPolicy objects.
    #
    # Gateway API and Envoy Gateway CRDs are shared by the whole cluster, so the
    # script is conservative and handles each family on its own:
    #   - absent altogether          -> install the pinned bundle
    #   - older than the pin         -> upgrade server-side to the pinned bundle
    #   - same as the pin            -> keep; create only individual missing CRDs
    #   - newer than the pin         -> keep untouched (never downgraded)
    #   - anything it cannot vouch for (unknown version or channel, partially
    #     installed, newer but incomplete, kubectl errors) -> stop and explain.
    # It never deletes CRDs or admission policies.
    local gateway_api_crd=gateways.gateway.networking.k8s.io
    local gateway_api_version=""
    local gateway_api_channel=""
    local gateway_api_action=install # install | upgrade | repair | keep
    local gateway_api_missing_crds=""
    local gateway_api_bundle_crds=""
    local eg_kubebuilder=""
    local eg_kb_minor=""
    local eg_crd_name="envoyproxies.gateway.envoyproxy.io"
    local eg_crds_action=install # install | upgrade | repair | keep
    local eg_missing_crds=""
    local eg_required_crds=""
    local all_crds_manifest=""
    local all_crd_names=""
    local missing_crds=""

    echo "Checking Gateway API and Envoy Gateway CRDs..."

    # The CRD lists come from the pinned bundle itself so they cannot drift.
    if ! all_crds_manifest=$(render_gateway_crds true true) || [ -z "$all_crds_manifest" ]; then
        echo "❌ Failed to render the Envoy Gateway ${envoy_gateway_version} CRD bundle (gateway-crds-helm). Check Helm/registry access and try again."
        exit 1
    fi
    all_crd_names=$(printf '%s\n' "$all_crds_manifest" | yq -r 'select(.kind == "CustomResourceDefinition") | .metadata.name' | grep -v '^---$')
    eg_required_crds=$(grep '\.gateway\.envoyproxy\.io$' <<<"$all_crd_names")
    gateway_api_bundle_crds=$(grep -E '\.gateway\.networking\.(k8s|x-k8s)\.io$' <<<"$all_crd_names")
    if [ -z "$eg_required_crds" ] || [ -z "$gateway_api_bundle_crds" ]; then
        echo "❌ The Envoy Gateway ${envoy_gateway_version} CRD bundle is missing Gateway API or Envoy Gateway CRDs; refusing to continue."
        exit 1
    fi

    # --- Gateway API CRDs ---
    if crd_present "$gateway_api_crd"; then
        gateway_api_version=$(crd_annotation "$gateway_api_crd" 'gateway\.networking\.k8s\.io/bundle-version') || exit 1
        gateway_api_channel=$(crd_annotation "$gateway_api_crd" 'gateway\.networking\.k8s\.io/channel') || exit 1
        if [ -z "$gateway_api_version" ]; then
            echo "❌ Gateway API CRDs are installed but carry no bundle-version annotation, so their version cannot be determined."
            echo "   The fast lane will not modify them. Make sure the cluster runs the experimental Gateway API bundle ${gateway_api_bundle_version} or newer, then rerun."
            exit 1
        fi
        case "$gateway_api_channel" in
        experimental) ;;
        "")
            echo "⚠️ Gateway API CRDs (bundle ${gateway_api_version}) carry no channel annotation; they will only be used as they are, never modified."
            ;;
        *)
            echo "❌ Gateway API CRDs are on the '${gateway_api_channel}' channel (bundle ${gateway_api_version}); the fast lane needs the experimental channel (a Traefik Gateway provider on the cluster needs TCPRoute)."
            echo "   The fast lane will not switch the channel of CRDs shared by the whole cluster. That is an operator decision:"
            echo "   the safe-upgrades ValidatingAdmissionPolicy blocks it, and removing the CRDs would also delete every Gateway API"
            echo "   resource (Gateways, HTTPRoutes, ...) in the cluster. Coordinate with the owners of those resources, move the"
            echo "   cluster to the experimental bundle ${gateway_api_bundle_version} or newer, then rerun."
            exit 1
            ;;
        esac

        if [ "$(printf '%s\n%s\n' "$gateway_api_bundle_version" "$gateway_api_version" | sort -V | head -n1)" = "$gateway_api_bundle_version" ]; then
            # Same as or newer than the pin: keep. The probe only looked at one CRD,
            # so check the ones Lamassu needs.
            # shellcheck disable=SC2086 # word splitting is intended: one CRD per word
            find_missing_crds $gateway_api_required_crds
            gateway_api_missing_crds="$missing_crds"
            if [ -z "$gateway_api_missing_crds" ]; then
                gateway_api_action=keep
                echo "✅ Gateway API CRDs already installed (bundle ${gateway_api_version}, channel ${gateway_api_channel:-unknown}); leaving them untouched."
            elif [ "$gateway_api_version" = "$gateway_api_bundle_version" ] && [ -n "$gateway_api_channel" ]; then
                gateway_api_action=repair
                echo "⚠️ Gateway API CRDs (bundle ${gateway_api_version}) are incomplete (missing: ${gateway_api_missing_crds}); creating only the missing ones."
            else
                echo "❌ Gateway API CRDs (bundle ${gateway_api_version}, channel ${gateway_api_channel:-unknown}) are incomplete (missing: ${gateway_api_missing_crds})."
                echo "   The fast lane only ships bundle ${gateway_api_bundle_version} and will not mix it into a different one. Restore the missing CRDs from the bundle installed on the cluster, then rerun."
                exit 1
            fi
        elif [ -z "$gateway_api_channel" ]; then
            echo "❌ Gateway API CRDs (bundle ${gateway_api_version}) are older than ${gateway_api_bundle_version} and their channel is unknown."
            echo "   The fast lane will not apply the experimental bundle over CRDs of an unknown channel. Upgrade them to the experimental bundle ${gateway_api_bundle_version} or newer, then rerun."
            exit 1
        else
            gateway_api_action=upgrade
            echo "⚠️ Gateway API CRDs are older (bundle ${gateway_api_version}) than the ${gateway_api_bundle_version} bundle shipped with Envoy Gateway ${envoy_gateway_version}; they will be upgraded server-side."
        fi
    else
        # shellcheck disable=SC2086 # word splitting is intended: one CRD per word
        find_missing_crds $gateway_api_bundle_crds
        if [ "$missing_crds" != "$(echo $gateway_api_bundle_crds)" ]; then
            echo "❌ ${gateway_api_crd} is missing but other Gateway API CRDs exist: the installation is partial and its version unknown."
            echo "   The fast lane will not modify it. Restore the Gateway API CRDs (experimental bundle ${gateway_api_bundle_version} or newer), then rerun."
            exit 1
        fi
        echo "Gateway API CRDs not found; installing the ${gateway_api_bundle_version} experimental bundle."
    fi

    # --- Envoy Gateway CRDs ---
    # Version probe: the controller-gen version that generated one CRD.
    if crd_present "$eg_crd_name"; then
        eg_kubebuilder=$(crd_annotation "$eg_crd_name" 'controller-gen\.kubebuilder\.io/version') || exit 1
        case "$eg_kubebuilder" in
        v0.[0-9]*.*)
            eg_kb_minor=${eg_kubebuilder#v0.}
            eg_kb_minor=${eg_kb_minor%%.*}
            ;;
        esac
        if [[ ! "$eg_kb_minor" =~ ^[0-9]+$ ]]; then
            echo "❌ Envoy Gateway CRDs carry an unrecognised kubebuilder version ('${eg_kubebuilder:-none}'), so their version cannot be determined."
            echo "   The fast lane will not modify them. Make sure the cluster runs the Envoy Gateway ${envoy_gateway_version} CRDs or newer, then rerun."
            exit 1
        fi

        # shellcheck disable=SC2086 # word splitting is intended: one CRD per word
        find_missing_crds $eg_required_crds
        eg_missing_crds="$missing_crds"
        if [ "$eg_kb_minor" -lt "$eg_kubebuilder_pinned_minor" ]; then
            eg_crds_action=upgrade
            echo "⚠️ Envoy Gateway CRDs are older (kubebuilder ${eg_kubebuilder}); they will be upgraded server-side to ${envoy_gateway_version}."
        elif [ -z "$eg_missing_crds" ]; then
            eg_crds_action=keep
            if [ "$eg_kb_minor" -eq "$eg_kubebuilder_pinned_minor" ]; then
                echo "✅ Envoy Gateway CRDs are up to date (kubebuilder ${eg_kubebuilder}); leaving them untouched."
            else
                echo "⚠️ Envoy Gateway CRDs are newer than the ones shipped with ${envoy_gateway_version} (kubebuilder ${eg_kubebuilder}); leaving them untouched."
            fi
        elif [ "$eg_kb_minor" -eq "$eg_kubebuilder_pinned_minor" ]; then
            eg_crds_action=repair
            echo "⚠️ Envoy Gateway CRDs (kubebuilder ${eg_kubebuilder}) are incomplete (missing: ${eg_missing_crds}); creating only the missing ones."
        else
            echo "❌ Envoy Gateway CRDs are newer than ${envoy_gateway_version} (kubebuilder ${eg_kubebuilder}) and incomplete (missing: ${eg_missing_crds})."
            echo "   The fast lane only ships the ${envoy_gateway_version} CRDs and will not mix them into a newer set. Restore the missing CRDs from the Envoy Gateway release installed on the cluster, then rerun."
            exit 1
        fi
    else
        # shellcheck disable=SC2086 # word splitting is intended: one CRD per word
        find_missing_crds $eg_required_crds
        if [ "$missing_crds" != "$(echo $eg_required_crds)" ]; then
            echo "❌ ${eg_crd_name} is missing but other Envoy Gateway CRDs exist: the installation is partial and its version unknown."
            echo "   The fast lane will not modify it. Restore the Envoy Gateway CRDs (${envoy_gateway_version} or newer), then rerun."
            exit 1
        fi
        echo "Envoy Gateway CRDs not found; installing the ${envoy_gateway_version} bundle."
    fi

    # --- Apply ---
    local apply_gateway_api=false
    local apply_eg_crds=false
    { [ "$gateway_api_action" = install ] || [ "$gateway_api_action" = upgrade ]; } && apply_gateway_api=true
    { [ "$eg_crds_action" = install ] || [ "$eg_crds_action" = upgrade ]; } && apply_eg_crds=true

    if [ "$apply_gateway_api" = true ] || [ "$apply_eg_crds" = true ]; then
        local crds_manifest=""
        echo "Applying CRDs via kubectl (Gateway API: ${apply_gateway_api}, Envoy Gateway: ${apply_eg_crds}); Envoy Gateway itself comes later, without CRDs..."
        if ! crds_manifest=$(render_gateway_crds "$apply_gateway_api" "$apply_eg_crds") || [ -z "$crds_manifest" ]; then
            echo "❌ Failed to render the CRD bundle. Please check Helm output and try again."
            exit 1
        fi
        if printf '%s\n' "$crds_manifest" | run_kubectl apply --server-side --force-conflicts -f -; then
            echo "✅ CRDs applied successfully"
        else
            echo "❌ Failed to apply CRDs. Please check Helm/Kubernetes output and try again."
            exit 1
        fi
    fi

    # Repairs use "kubectl create": it only adds the missing CRD and fails rather
    # than modify one that turned out to exist.
    local crd
    for crd in $([ "$gateway_api_action" = repair ] && echo "$gateway_api_missing_crds") \
        $([ "$eg_crds_action" = repair ] && echo "$eg_missing_crds"); do
        if CRD_NAME="$crd" yq 'select(.kind == "CustomResourceDefinition" and .metadata.name == env(CRD_NAME))' <<<"$all_crds_manifest" | run_kubectl create -f -; then
            echo "✅ Created missing CRD ${crd}"
        else
            echo "❌ Failed to create missing CRD ${crd}. Please check Kubernetes output and try again."
            exit 1
        fi
    done

    # shellcheck disable=SC2086 # word splitting is intended: one CRD per word
    find_missing_crds $gateway_api_required_crds $eg_required_crds
    if [ -n "$missing_crds" ]; then
        echo "❌ Required CRDs are missing: ${missing_crds}"
        echo "   Both Envoy Gateway charts are installed with --skip-crds, so nothing would create them. Check the CRD output above and rerun."
        exit 1
    fi
    echo "✅ All required Gateway API and Envoy Gateway CRDs are present"

    # 2. Check Helm Release
    if run_helm list -n envoy-gateway-system | grep -q "^eg\s"; then
        echo "✅ Envoy Gateway (eg) Helm release found"
        echo "Upgrading Envoy Gateway to ${envoy_gateway_version}..."
        if run_helm upgrade eg oci://docker.io/envoyproxy/gateway-helm --version "${envoy_gateway_version}" -n envoy-gateway-system --skip-crds; then
            echo "✅ Envoy Gateway Helm chart 'eg' upgraded successfully"
        else
            echo "❌ Failed to upgrade Envoy Gateway Helm chart 'eg'. Please check Helm output and try again."
            exit 1
        fi
    else
        echo "❌ Envoy Gateway: Helm release 'eg' not found in namespace 'envoy-gateway-system'"
        echo "Installing Envoy Gateway ${envoy_gateway_version} (CRDs are already installed, skipping Helm CRDs)..."
        if run_helm install eg oci://docker.io/envoyproxy/gateway-helm --version "${envoy_gateway_version}" -n envoy-gateway-system --create-namespace --skip-crds; then
            echo "✅ Envoy Gateway Helm chart 'eg' installed successfully"
        else
            echo "❌ Failed to install Envoy Gateway Helm chart 'eg'. Please check Helm output and try again."
            exit 1
        fi
    fi

    # 3. Check/Create GatewayClass
    if run_kubectl get gatewayclass eg >/dev/null 2>&1; then
        echo "✅ GatewayClass 'eg' already exists"
    else
        echo "Missing GatewayClass 'eg'. Applying now..."
        cat <<EOF | run_kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
        
        if [ $? -eq 0 ]; then
            echo "✅ GatewayClass 'eg' created successfully"
        else
            echo "❌ Failed to create GatewayClass 'eg'. Ensure Gateway API CRDs are installed."
            exit 1
        fi
    fi
}

function install_observability() {
    echo -e "${ORANGE}Installing Victoria Logs...${NOCOLOR}"
    cat >victoria-logs.yaml <<"EOF"
server:
  fullnameOverride: "victoria-logs"
  persistentVolume:
    enabled: false
EOF

    victoria_logs_helm_path=vm/victoria-logs-single
    run_helm repo add vm https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
    run_helm repo update vm 2>/dev/null || true

    run_helm install victoria-logs $victoria_logs_helm_path -n $NAMESPACE -f victoria-logs.yaml --wait
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Victoria Logs installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing Victoria Logs${NOCOLOR}"
        exit 1
    fi

    echo -e "${ORANGE}Installing VictoriaTraces...${NOCOLOR}"
    cat >victoria-traces.yaml <<"EOF"
server:
  fullnameOverride: "victoria-traces"
  persistentVolume:
    enabled: false
EOF

    victoria_traces_helm_path=vm/victoria-traces-single
    run_helm repo add vm https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
    run_helm repo update vm 2>/dev/null || true

    run_helm install victoria-traces $victoria_traces_helm_path -n $NAMESPACE -f victoria-traces.yaml --wait
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}VictoriaTraces installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing VictoriaTraces${NOCOLOR}"
        exit 1
    fi

    echo -e "${ORANGE}Installing Jaeger...${NOCOLOR}"
    cat >jaeger.yaml <<"EOF"
fullnameOverride: jaeger
userconfig:
  service:
    extensions: [jaeger_storage, jaeger_query, healthcheckv2]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [jaeger_storage_exporter]
  extensions:
    healthcheckv2:
      use_v2: true
      http:
        endpoint: 0.0.0.0:13133
    jaeger_query:
      base_path: /infra/jaeger
      storage:
        traces: main_store
    jaeger_storage:
      backends:
        main_store:
          memory:
            max_traces: 100000
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch: {}
  exporters:
    jaeger_storage_exporter:
      trace_storage: main_store
EOF

    jaeger_helm_path=jaegertracing/jaeger
    run_helm repo add jaegertracing https://jaegertracing.github.io/helm-charts 2>/dev/null || true
    run_helm repo update jaegertracing 2>/dev/null || true

    run_helm install jaeger $jaeger_helm_path -n $NAMESPACE -f jaeger.yaml --wait
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Jaeger installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing Jaeger${NOCOLOR}"
        exit 1
    fi

    echo -e "${ORANGE}Installing OTel Collector...${NOCOLOR}"
    cat >otel-collector.yaml <<"EOF"
mode: deployment
fullnameOverride: otel-collector
image:
  repository: otel/opentelemetry-collector-contrib
config:
  exporters:
    otlphttp/jaeger:
      traces_endpoint: http://jaeger:4318/v1/traces
      tls:
        insecure: true
    otlphttp/victoriatraces:
      traces_endpoint: http://victoria-traces:10428/insert/opentelemetry/v1/traces
      tls:
        insecure: true
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlphttp/jaeger, otlphttp/victoriatraces]
EOF

    otel_collector_helm_path=open-telemetry/opentelemetry-collector
    run_helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
    run_helm repo update open-telemetry 2>/dev/null || true

    run_helm install otel-collector $otel_collector_helm_path -n $NAMESPACE -f otel-collector.yaml --wait
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}OTel Collector installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing OTel Collector${NOCOLOR}"
        exit 1
    fi
}

main "$@"
