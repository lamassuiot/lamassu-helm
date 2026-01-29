#!/bin/bash

dist=
kube=
kubectl="kubectl"
helm="helm"

DOMAIN=dev.lamassu.io
DOMAIN_OVERRIDE=false
NAMESPACE=lamassu-dev
NAMESPACE_OVERRIDE=false
OFFLINE=false
NON_INTERACTIVE=false
HTTPS_PORT=443
HTTP_PORT=80
LAMASSU_CHART_PATH="lamassuiot/lamassu"
LAMASSU_USE_LOCAL_PATH=false

TLS_CRT=
TLS_KEY=

POSTGRES_USER=admin
POSTGRES_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} {.,@,$} | tr -d '\n'
    echo
)
RABBIT_USER=admin
RABBIT_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} {.,@,$} | tr -d '\n'
    echo
)

KEYCLOAK_USER=admin
KEYCLOAK_PWD=$(
    shuf -er -n30  {A..Z} {a..z} {0..9} {.,@,$} | tr -d '\n'
    echo
)

OFFLINE_HELMCHART_LAMASSU=""
OFFLINE_HELMCHART_RABBITMQ=""
OFFLINE_HELMCHART_KEYCLOAK=""
OFFLINE_HELMCHART_POSTGRES=""


function main() {
    init

    process_flags "$@"

    detect_distribution
    if [ $dist == "microk8s" ]; then
        kube="microk8s"
    fi

    if [ "$OFFLINE" = true ]; then
        echo -e "${ORANGE}Offline mode enabled. Images must be already imported${NOCOLOR}"

        if [ "$OFFLINE_HELMCHART_LAMASSU" = "" ]; then
            echo -e "\n${RED}Lamassu helm chart path is empty${NOCOLOR}"
            exit 1
        fi
        if [ "$OFFLINE_HELMCHART_RABBITMQ" = "" ]; then
            echo -e "\n${RED}RabbitMQ helm chart path is empty${NOCOLOR}"
            exit 1
        fi
        if [ "$OFFLINE_HELMCHART_KEYCLOAK" = "" ]; then
            echo -e "\n${RED}Keycloak helm chart path is empty${NOCOLOR}"
            exit 1
        fi
        if [ "$OFFLINE_HELMCHART_POSTGRES" = "" ]; then
            echo -e "\n${RED}Postgres helm chart path is empty${NOCOLOR}"
            exit 1
        fi
    else
        echo -e "${ORANGE}ONLINE MODE ENABLED${NOCOLOR}"
    fi

    echo -e "${BLUE}=== Installing Lamassu IoT using Fast Lane ===${NOCOLOR}"
    echo -e "\n${BLUE}1) Dependencies checking${NOCOLOR}"
    check_dependencies
    echo -e "\n${BLUE}2) Provide minimal config info${NOCOLOR}"
    request_config_data
    echo -e "\n${BLUE}3) Create ${NAMESPACE} namespace${NOCOLOR}"
    create_kubernetes_namespace
    echo -e "\n${BLUE}4) Install PostgreSQL${NOCOLOR}"
    install_postgresql
    echo -e "\n${BLUE}5) Install Auth - Keycloak${NOCOLOR}"
    install_keycloak
    echo -e "\n${BLUE}6) Install RabbitMQ${NOCOLOR}"
    install_rabbitmq
    echo -e "\n${BLUE}7) Install Lamassu IoT. It may take a few minutes${NOCOLOR}"
    install_lamassu

    final_instructions
}

function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo " -h, --help                   Display this help message"
    echo " -n, --non-interactive        Enable non-interactive mode. Credentials for Keycloak, Postgres and RabbitMQ will be auto generated"
    echo " -ns, --namespace             Kubernetes Namespace where LAMASSU will be deployed"
    echo " -d, --domain                 Domain to be set while deploying LAMASSU"
    echo " -v, --version                Version of the Lamassu Helm Chart to be installed. Default is latest"
    echo " --https-port                 HTTPS port to be used for Lamassu IoT. Default is 443"
    echo " --http-port                  HTTP port to be used for Lamassu IoT. Default is 80"
    echo " --offline                    Offline mode enabled. Use local helm charts (--helm-chart-rabbitmq, --helm-chart-postgres and --helm-chart-lamassu flags will be required)"
    echo " --tls-crt                    Path to the PEM encoded certificate used for downstream communications"
    echo " --tls-key                    Path to the PEM encoded key used for downstream communications"
    echo " --helm-chart-lamassu         (Only needed while using --offline) Path to the Lamassu helm chart (.tgz format)"
    echo " --helm-chart-postgres        (Only needed while using --offline) Path to the Posgtres helm chart (.tgz format)"
    echo " --helm-chart-keycloak        (Only needed while using --offline) Path to the Keycloak helm chart (.tgz format)"
    echo " --helm-chart-rabbitmq        (Only needed while using --offline) Path to the RabbitMQ helm chart (.tgz format)"
    echo " -l, --local-chart-path       Path to the local chart folder"
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
        --offline)
            OFFLINE=true
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
         --helm-chart-lamassu)
              if ! has_argument $@; then
                echo -e "\n${RED}Lamassu Helm Chart not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            OFFLINE_HELMCHART_LAMASSU=$(extract_argument $@)

            shift
            ;;
         --helm-chart-postgres)
              if ! has_argument $@; then
                echo -e "\n${RED}Postgres Helm Chart not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            OFFLINE_HELMCHART_POSTGRES=$(extract_argument $@)

            shift
            ;;
         --helm-chart-rabbitmq)
              if ! has_argument $@; then
                echo -e "\n${RED}Rabbitmq Helm Chart not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            OFFLINE_HELMCHART_RABBITMQ=$(extract_argument $@)

            shift
            ;;
         --helm-chart-keycloak)
              if ! has_argument $@; then
                echo -e "\n${RED}Keycloak Helm Chart not specified.${NOCOLOR}" >&2
                usage
                exit 1
            fi
            OFFLINE_HELMCHART_KEYCLOAK=$(extract_argument $@)

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
    echo -e "${BLUE}Please connect to https://${DOMAIN} using default user lamassu/lamassu ${NOCOLOR}"
    echo -e "${BLUE}You will be required to change the password on the first connection${NOCOLOR}"
    echo -e "${BLUE}If more users are needed connect to  https://${DOMAIN}/auth/admin${NOCOLOR}"
    echo -e "${BLUE}Use the provided Keycloak credentials ${KEYCLOAK_USER}/${KEYCLOAK_PWD}${NOCOLOR}"
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

auth:
  oidc:
    apiGateway:
      jwks:
        - name: oidc-authn
          uri: http://auth-keycloak/auth/realms/lamassu/protocol/openid-connect/certs

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

export IP_LIST="$(hostname -I)"
export HTTPS_PORT=$HTTPS_PORT
export HTTP_PORT=$HTTP_PORT

yq -i '.gateway.addresses = (env(IP_LIST) | split(" "))' lamassu.yaml
yq -i '.gateway.ports.https = env(HTTPS_PORT)' lamassu.yaml
yq -i '.gateway.ports.http = env(HTTP_PORT)' lamassu.yaml

export NAMESPACE=$NAMESPACE
yq -i '.auth.oidc.apiGateway.jwks[0].uri = "http://auth-keycloak." + env(NAMESPACE) + "/auth/realms/lamassu/protocol/openid-connect/certs"' lamassu.yaml

# Check if TLS_CRT and TLS_KEY are not empty
if [[ -n "$TLS_CRT" && -n "$TLS_KEY" ]]; then
    echo -e "${ORANGE}Deploying Lamassu with EXTERNAL TLS Certificates${NOCOLOR}"

    $kube $kubectl create secret tls downstream-provided-crt --cert=$TLS_CRT --key=$TLS_KEY -n $NAMESPACE

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
    yq -i '.tls.certManagerOptions.issuer = "downstream-ca-selfsigned-issuer"' lamassu.yaml
    yq -i '.tls.certManagerOptions.certSpec.commonName = (env(DOMAIN))' lamassu.yaml
    yq -i '.tls.certManagerOptions.certSpec.addresses = (env(IP_LIST) | split(" "))' lamassu.yaml
fi


    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    export RABBIT_USER=$RABBIT_USER
    export RABBIT_PWD=$RABBIT_PWD

    yq -i '.postgres.username = (env(POSTGRES_USER))' lamassu.yaml
    yq -i '.postgres.password = (env(POSTGRES_PWD))' lamassu.yaml
    yq -i '.amqp.username = (env(RABBIT_USER))' lamassu.yaml
    yq -i '.amqp.password = (env(RABBIT_PWD))' lamassu.yaml


    helm_path=$LAMASSU_CHART_PATH
    if [ "$OFFLINE" = false ]; then
      if [ "$LAMASSU_USE_LOCAL_PATH" = false ]; then
        $kube $helm repo add lamassuiot http://www.lamassu.io/lamassu-helm/
      else
        echo -e "${ORANGE}Using local chart path ${LAMASSU_CHART_PATH} ${NOCOLOR}"
      fi
    else
        cat >offline.yaml <<"EOF"
global:
  imagePullPolicy: Never
EOF
        yq eval-all '. as $item ireduce ({}; . * $item )' lamassu.yaml offline.yaml -i
        rm offline.yaml
        helm_path=$OFFLINE_HELMCHART_LAMASSU
    fi

    helm_version=""
    if [ "$VERSION_OVERRIDE" = true ]; then
        helm_version="--version $VERSION"
    fi

    $kube $helm install -n $NAMESPACE lamassu $helm_path $helm_version -f lamassu.yaml --wait

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}Lamassu IoT installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing Lamassu IoT${NOCOLOR}"
        exit 1
    fi
}

function install_rabbitmq() {
    helm_path=bitnami/rabbitmq
    if [ "$OFFLINE" = false ]; then
        $kube $helm repo add bitnami https://charts.bitnami.com/bitnami
        $kube $helm repo update
    else
        helm_path=$OFFLINE_HELMCHART_RABBITMQ
    fi
    cat >rabbitmq.yaml <<"EOF"
fullnameOverride: "rabbitmq"

global:
  security:
    allowInsecureImages: true

image:
  registry: docker.io
  repository: bitnamilegacy/rabbitmq
  #tag: 4.1.3-debian-12-r1

auth:
  username:
  password:
EOF

   export RABBIT_USER=$RABBIT_USER
   export RABBIT_PWD=$RABBIT_PWD

   yq -i '.auth.username = env(RABBIT_USER)' rabbitmq.yaml
   yq -i '.auth.password = env(RABBIT_PWD)' rabbitmq.yaml
   
   $kube $helm install rabbitmq $helm_path --version 12.6.0 -n $NAMESPACE -f rabbitmq.yaml --wait
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
  repository: bitnamilegacy/keycloak
  tag: 25.0.2-debian-12-r1

auth:
  adminUser: ""
  adminPassword: ""

postgresql:
  enabled: false

externalDatabase:
  host: "postgresql"
  port: 5432
  user: ""
  password: ""
  database: auth

logging:
  level: INFO

httpRelativePath: /auth/
proxy: reencrypt
proxyHeaders: xforwarded

extraEnvVars:
  - name: KC_HOSTNAME_STRICT
    value: "false"
  - name: KC_HEALTH_ENABLED
    value: "true"
  - name: KC_LEGACY_OBSERVABILITY_INTERFACE
    value: "true"
  - name: HTTP_ADDRESS_FORWARDING
    value: "true"
  - name: QUARKUS_HTTP_ACCESS_LOG_ENABLED
    value: "true"
  - name: QUARKUS_HTTP_ACCESS_LOG_PATTERN
    value: "%r\n%{ALL_REQUEST_HEADERS}"

keycloakConfigCli:
  enabled: true
  image:
    registry: docker.io
    repository: bitnamilegacy/keycloak-config-cli
    tag: 6.1.6-debian-12-r0
  configuration:
    realm-configuration.yaml: |
      realm: lamassu
      enabled: true
      loginTheme: keycloakify-starter
      roles:
        realm:
        - name: pki-admin
          description: "PKI Full Access"
      users:
      - username: lamassu
        enabled: true
        credentials:
        - type: password
          value: lamassu
          temporary: true
        requiredActions:
        - UPDATE_PASSWORD
        realmRoles:
        - pki-admin
      clients:
      - clientId: frontend
        enabled: true
        redirectUris:
        - "/*"
        webOrigins:
        - "/*"
        publicClient: true
        directAccessGrantsEnabled: true
EOF

    if [ "$OFFLINE" = false ]; then
        cat >>keycloak.yaml <<"EOF"
extraVolumes:
  - name: extensions
    emptyDir: {}

extraVolumeMounts: 
  - name: extensions
    mountPath: /opt/bitnami/keycloak/providers

initContainers:
- name: init-custom-theme
  image: curlimages/curl:8.10.1
  command: ['sh', '-c', 'curl -L -f -S -o /extensions/lamassu-theme.jar https://github.com/lamassuiot/keycloak-theme/releases/download/2.0.0/keycloak-theme-for-kc-22-to-25.jar']
  volumeMounts:  
  - mountPath: "/extensions"
    name: extensions
EOF
    fi


    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    yq -i '.externalDatabase.user = env(POSTGRES_USER)' keycloak.yaml
    yq -i '.externalDatabase.password = env(POSTGRES_PWD)' keycloak.yaml

    export KEYCLOAK_USER=$KEYCLOAK_USER
    export KEYCLOAK_PWD=$KEYCLOAK_PWD
    yq -i '.auth.adminUser = env(KEYCLOAK_USER)' keycloak.yaml
    yq -i '.auth.adminPassword = env(KEYCLOAK_PWD)' keycloak.yaml


    helm_path=bitnami/keycloak
    if [ "$OFFLINE" = false ]; then
        $kube $helm repo add bitnami https://charts.bitnami.com/bitnami
        $kube $helm repo update
    else
        helm_path=$OFFLINE_HELMCHART_KEYCLOAK
    fi

    $kube $helm install auth $helm_path --version 22.1.1 -n $NAMESPACE --wait -f keycloak.yaml
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
  repository: bitnamilegacy/postgresql
global:
  security:
    allowInsecureImages: true
  postgresql:
    auth:
      username: ""
      password: ""
primary:
  initdb:
    scripts:
      init.sql: |
        CREATE DATABASE auth;
        CREATE DATABASE alerts;
        CREATE DATABASE ca;
        CREATE DATABASE va;
        CREATE DATABASE cloudproxy;
        CREATE DATABASE devicemanager;
        CREATE DATABASE dmsmanager;
        CREATE DATABASE kms;
EOF

    export POSTGRES_USER=$POSTGRES_USER
    export POSTGRES_PWD=$POSTGRES_PWD
    yq -i '.global.postgresql.auth.username = env(POSTGRES_USER)' postgres.yaml
    yq -i '.global.postgresql.auth.password = env(POSTGRES_PWD)' postgres.yaml

    helm_path=bitnami/postgresql
    if [ "$OFFLINE" = false ]; then
        $kube $helm repo add bitnami https://charts.bitnami.com/bitnami
    else
        helm_path=$OFFLINE_HELMCHART_POSTGRES
    fi

    $kube $helm install postgres $helm_path -n $NAMESPACE --version 16.7.27 -f postgres.yaml --wait
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}PostgreSQL installed${NOCOLOR}"
    else
        echo -e "\n${RED}Error installing PostgreSQL${NOCOLOR}"
        exit 1
    fi
}

function create_kubernetes_namespace() {
    # Check if the namespace exists
    if $kube $kubectl get ns "$NAMESPACE" &> /dev/null; then
        echo -e "\n${GREEN}Namespace $NAMESPACE already exists${NOCOLOR}"
    else
        # If the namespace doesn't exist, create it
        $kube $kubectl create ns $NAMESPACE
        echo "Namespace $NAMESPACE created."
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}Namespace $NAMESPACE created${NOCOLOR}"
        else
            echo -e "\n${RED}Error creating namespace $NAMESPACE${NOCOLOR}"
            exit 1
        fi
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
        RABBIT_USER=$req
    fi
}

function request_keycloak_pwd() {
    echo -n "Keycloak admin password ($KEYCLOAK_PWD): "
    read req
    if [ "$req" != "" ]; then
        RABBIT_PWD=$req
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
    echo -e "${RED}No kubernetes distribution found${NOCOLOR}"
    exit 1
}

function check_dependencies() {
    exit_if_command_not_installed yq
    exit_if_command_not_installed $dist
    if [ $dist == "k3s" ]; then
        exit_if_command_not_installed $kubectl
        exit_if_command_not_installed $helm
    fi

    if [ $dist == "microk8s" ]; then
        exit_if_kube_command_not_installed $kubectl
        exit_if_kube_command_not_installed $helm
        check_microk8s_minimum_requirements
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
    # 1. Check Helm Release
    if $kube $helm list -n envoy-gateway-system | grep -q "^eg\s"; then
        echo "✅ Envoy Gateway (eg) Helm release found"
    else
        echo "❌ Envoy Gateway: Helm release 'eg' not found in namespace 'envoy-gateway-system'"
        echo "Installing Envoy Gateway v1.3.0..."
        if $kube $helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.3.0 -n envoy-gateway-system --create-namespace; then
            echo "✅ Envoy Gateway Helm chart 'eg' installed successfully"
        else
            echo "❌ Failed to install Envoy Gateway Helm chart 'eg'. Please check Helm output and try again."
            exit 1
        fi
    fi

    # 2. Check/Create GatewayClass
    if $kube kubectl get gatewayclass eg >/dev/null 2>&1; then
        echo "✅ GatewayClass 'eg' already exists"
    else
        echo "Missing GatewayClass 'eg'. Applying now..."
        cat <<EOF | $kube kubectl apply -f -
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

main "$@"
