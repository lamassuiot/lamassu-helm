#!/bin/bash
################################################################################
# Sample data populator (curl/jq/openssl port of
# monolithic/pkg/sampledata/generator.go @ tag monolithic/v3.8.0)
#
# Recreates, via the public REST API, what PopulateSampleData() does when the
# monolithic binary is started with --sample-data / populate_sample_data=true:
#   1. CA issuance profiles (imported-root profile, generated-root profile)
#   2. An imported ECDSA P-256 root CA (key generated locally, imported into KMS)
#   3. A generated ECDSA P-256 root CA
#   4. Certificate issuance profiles: server / client / device
#   5. 4 sample certificates issued from each of the two root CAs
#   6. A sample DMS (EST/JITP enrollment, bound to the imported CA)
#   7. 50 sample devices (varied tags/icons/metadata for device-group testing)
#   8. Certificates issued + bound (BindIdentityToDevice) for the first 10 devices
#
# Usage:
#   ./scripts/sample-data.sh [server]
#
# Env overrides:
#   SERVER               Lamassu gateway base URL (default: http://localhost:8080)
#   WORKDIR              scratch dir for generated keys/CSRs/certs (default: mktemp -d)
#
# OIDC (only needed if the gateway enforces auth, e.g. via the authz/ext-authz
# connector or an HTTPClient configured with auth_mode: jwt). Discovers the
# token endpoint from the OIDC well-known URL, then requests a token:
#   OIDC_WELL_KNOWN_URL  e.g. https://idp.example.com/realms/lamassu/.well-known/openid-configuration
#   OIDC_CLIENT_ID       client id
#   OIDC_CLIENT_SECRET   confidential client secret — set this for a confidential
#                        client (uses grant_type=client_credentials)
#   OIDC_USERNAME        \_ for a PUBLIC client (no secret): uses
#   OIDC_PASSWORD        /  grant_type=password (Resource Owner Password Credentials)
#   OIDC_SCOPE           optional extra scope(s), space separated
#   ACCESS_TOKEN         alternatively, pass an already-issued bearer token directly
#                        (skips OIDC discovery/token-request entirely)
#
# Required tools: curl, jq, openssl, base64.
#
# The script is idempotent-ish: like the Go generator, failures on individual
# "already exists" steps are logged and skipped rather than aborting the run.
#
# TLS: like generator.go's http.Client (InsecureSkipVerify: true), TLS
# certificate verification is skipped by default, since this tool targets
# dev/lab deployments that often terminate TLS with a self-signed cert.
# Set INSECURE_SKIP_VERIFY=false to enforce normal certificate validation.
################################################################################
set -uo pipefail

SERVER="${1:-${SERVER:-http://localhost:8080}}"
WORKDIR="${WORKDIR:-$(mktemp -d /tmp/lamassu-sample-data.XXXXXX)}"
mkdir -p "${WORKDIR}"

CA_URL="${SERVER}/api/ca"
KMS_URL="${SERVER}/api/kms"
DMS_URL="${SERVER}/api/dmsmanager"
DEV_URL="${SERVER}/api/devmanager"

TLS_ARGS=()
if [ "${INSECURE_SKIP_VERIFY:-true}" != "false" ]; then
    TLS_ARGS=(-k)
fi

log()  { echo "[sample-data] $*" >&2; }
warn() { echo "[sample-data] WARN: $*" >&2; }

# ------------------------------------------------------------------------- #
# OIDC bearer token (client_credentials grant), if configured
# ------------------------------------------------------------------------- #
AUTH_ARGS=()

# fetch_oidc_token <well_known_url> <client_id> [client_secret] [username] [password] [scope]
# Uses client_credentials when a client_secret is given (confidential client);
# otherwise falls back to the password grant with username/password (public client).
fetch_oidc_token() {
    local well_known="$1" client_id="$2" client_secret="${3:-}" username="${4:-}" password="${5:-}" scope="${6:-}"
    local token_url token_resp token data http_out status

    http_out=$(curl -s "${TLS_ARGS[@]}" -w $'\n''%{http_code}' "${well_known}")
    status="${http_out##*$'\n'}"
    log "GET ${well_known} -> ${status}"
    token_url=$(printf '%s' "${http_out%$'\n'*}" | jq -r '.token_endpoint // empty' 2>/dev/null)
    if [ -z "${token_url}" ]; then
        warn "could not discover token_endpoint from ${well_known} (HTTP ${status}, not a valid OIDC discovery document)"
        return 1
    fi

    if [ -n "${client_secret}" ]; then
        data="grant_type=client_credentials&client_id=${client_id}&client_secret=${client_secret}"
    elif [ -n "${username}" ] && [ -n "${password}" ]; then
        data="grant_type=password&client_id=${client_id}&username=${username}&password=${password}"
    else
        warn "no OIDC_CLIENT_SECRET (confidential client) or OIDC_USERNAME/OIDC_PASSWORD (public client) provided"
        return 1
    fi
    [ -n "${scope}" ] && data="${data}&scope=${scope}"

    http_out=$(curl -s "${TLS_ARGS[@]}" -X POST "${token_url}" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "${data}" \
        -w $'\n''%{http_code}')
    status="${http_out##*$'\n'}"
    log "POST ${token_url} -> ${status}"
    token_resp="${http_out%$'\n'*}"
    if [[ "${status}" != 2* ]]; then
        warn "token request to ${token_url} failed (HTTP ${status}): ${token_resp}"
        return 1
    fi

    token=$(echo "${token_resp}" | jq -r '.access_token // empty')
    [ -n "${token}" ] || { warn "token response missing access_token: ${token_resp}"; return 1; }
    echo "${token}"
}

if [ -n "${ACCESS_TOKEN:-}" ]; then
    AUTH_ARGS=(-H "Authorization: Bearer ${ACCESS_TOKEN}")
    log "Using externally supplied ACCESS_TOKEN for authentication"
elif [ -n "${OIDC_CLIENT_ID:-}" ] && [ -n "${OIDC_WELL_KNOWN_URL:-}" ]; then
    log "Authenticating against OIDC provider: ${OIDC_WELL_KNOWN_URL}"
    ACCESS_TOKEN=$(fetch_oidc_token "${OIDC_WELL_KNOWN_URL}" "${OIDC_CLIENT_ID}" \
        "${OIDC_CLIENT_SECRET:-}" "${OIDC_USERNAME:-}" "${OIDC_PASSWORD:-}" "${OIDC_SCOPE:-}")
    if [ -z "${ACCESS_TOKEN}" ]; then
        warn "could not obtain OIDC access token, aborting"
        exit 1
    fi
    AUTH_ARGS=(-H "Authorization: Bearer ${ACCESS_TOKEN}")
    log "Obtained OIDC access token"
fi

# curl wrapper: injects the bearer token (if any), logs "METHOD URL -> STATUS"
# for every API call, and prints the response body. Expects the convention
# used throughout this script: `api_call -X <METHOD> <URL> [curl-args...]`.
# Returns non-zero (after logging) on connection failure or a non-2xx status.
api_call() {
    local method="$2" url="$3"
    local http_out curl_rc status body

    http_out=$(curl -s "${TLS_ARGS[@]}" "${AUTH_ARGS[@]}" -w $'\n''%{http_code}' "$@")
    curl_rc=$?
    status="${http_out##*$'\n'}"
    body="${http_out%$'\n'*}"
    log "${method} ${url} -> ${status}"
    printf '%s' "${body}"

    [ "${curl_rc}" -eq 0 ] || return 1
    [[ "${status}" == 2* ]]
}

# ------------------------------------------------------------------------- #
# helpers
# ------------------------------------------------------------------------- #

# create_issuance_profile <name> <description> <validity_duration> <sign_as_ca>
#                          <key_usage_json_array> <ext_key_usage_json_array> <honor_subject>
# Prints the created profile's id on success (empty on failure).
create_issuance_profile() {
    local name="$1" description="$2" validity="$3" sign_as_ca="$4"
    local key_usage="$5" ext_key_usage="$6" honor_subject="$7"
    local resp rc id

    resp=$(api_call -X POST "${CA_URL}/v1/profiles" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n \
            --arg name "$name" \
            --arg description "$description" \
            --arg validity "$validity" \
            --argjson sign_as_ca "$sign_as_ca" \
            --argjson key_usage "$key_usage" \
            --argjson ext_key_usage "$ext_key_usage" \
            --argjson honor_subject "$honor_subject" \
            '{
                name: $name,
                description: $description,
                validity: {type: "Duration", duration: $validity},
                sign_as_ca: $sign_as_ca,
                honor_key_usage: false,
                key_usage: $key_usage,
                honor_extended_key_usages: false,
                extended_key_usages: $ext_key_usage,
                honor_subject: $honor_subject,
                subject: {}
            }')")
    rc=$?
    if [ ${rc} -ne 0 ]; then
        warn "could not create issuance profile '${name}': ${resp}"
        return 0
    fi
    id=$(echo "${resp}" | jq -r '.id // empty')
    if [ -z "${id}" ]; then
        warn "issuance profile '${name}' response missing id: ${resp}"
        return 0
    fi
    log "created issuance profile '${name}' (ID: ${id})"
    echo "${id}"
}

# csr_b64 <common_name> <organization> <key_out> [dns_name ...]
# Generates an EC P-256 key + CSR and prints base64(PEM CSR).
csr_b64() {
    local cn="$1" org="$2" keyfile="$3"; shift 3
    local dns=("$@")
    local csrfile="${keyfile%.key}.csr"

    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
        -out "${keyfile}" 2>/dev/null

    if [ "${#dns[@]}" -gt 0 ]; then
        local san="" d
        for d in "${dns[@]}"; do
            san="${san:+${san},}DNS:${d}"
        done
        openssl req -new -key "${keyfile}" -out "${csrfile}" \
            -subj "/CN=${cn}/O=${org}" \
            -addext "subjectAltName=${san}" 2>/dev/null
    else
        openssl req -new -key "${keyfile}" -out "${csrfile}" \
            -subj "/CN=${cn}/O=${org}" 2>/dev/null
    fi

    openssl req -in "${csrfile}" -outform PEM 2>/dev/null | base64 -w0
}

# sign_certificate <ca_id> <profile_id> <csr_b64>
# Prints the signed certificate's serial number on success.
sign_certificate() {
    local ca_id="$1" profile_id="$2" csr="$3"
    local resp rc serial

    resp=$(api_call -X POST "${CA_URL}/v1/cas/${ca_id}/certificates/sign" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg csr "$csr" --arg profile_id "$profile_id" \
            '{csr: $csr, profile_id: $profile_id}')")
    rc=$?
    if [ ${rc} -ne 0 ]; then
        return 1
    fi
    serial=$(echo "${resp}" | jq -r '.serial_number // empty')
    [ -n "${serial}" ] || return 1
    echo "${serial}"
}

# ------------------------------------------------------------------------- #
# Step 1: CA issuance profiles
# ------------------------------------------------------------------------- #
log "Creating CA issuance profiles..."

IMPORTED_ROOT_CA_PROFILE_ID=$(create_issuance_profile \
    "Imported Root CA Profile" "Profile for the imported root CA" \
    "3650d" false '["CertSign","CRLSign","DigitalSignature"]' '[]' true)

GENERATED_ROOT_CA_PROFILE_ID=$(create_issuance_profile \
    "Generated Root CA Profile" "Profile for the generated root CA" \
    "3650d" false '["CertSign","CRLSign","DigitalSignature"]' '[]' true)

# ------------------------------------------------------------------------- #
# Step 2: import a private key into KMS and create the Imported Root CA
# ------------------------------------------------------------------------- #
log "Importing private key into KMS and creating Root CA..."

IMPORTED_CA_ID=""
if [ -n "${IMPORTED_ROOT_CA_PROFILE_ID}" ]; then
    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 \
        -out "${WORKDIR}/imported-root-ca.key" 2>/dev/null
    IMPORTED_KEY_PEM_B64=$(base64 -w0 "${WORKDIR}/imported-root-ca.key")

    IMPORT_RESP=$(api_call -X POST "${KMS_URL}/v1/keys/import" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg key "${IMPORTED_KEY_PEM_B64}" '{
            private_key: $key,
            name: "Sample Imported Root CA Key",
            tags: ["sample", "root-ca"],
            metadata: {sample: true, description: "Imported ECDSA P-256 key for sample root CA"}
        }')")
    IMPORT_RC=$?

    if [ ${IMPORT_RC} -ne 0 ]; then
        warn "could not import key into KMS: ${IMPORT_RESP}"
    else
        KMS_KEY_ID=$(echo "${IMPORT_RESP}" | jq -r '.key_id // empty')
        if [ -z "${KMS_KEY_ID}" ]; then
            warn "KMS import response missing key_id: ${IMPORT_RESP}"
        else
            log "Successfully imported key into KMS: ${KMS_KEY_ID}"
            CA_RESP=$(api_call -X POST "${CA_URL}/v1/cas" \
                -H 'Content-Type: application/json' \
                -d "$(jq -n --arg key_id "${KMS_KEY_ID}" --arg profile_id "${IMPORTED_ROOT_CA_PROFILE_ID}" '{
                    id: "sample-imported-root-ca",
                    subject: {
                        common_name: "Sample Imported Root CA",
                        organization: "LamassuIoT Sample",
                        organization_unit: "Development",
                        state: "Gipuzkoa",
                        locality: "Arrasate"
                    },
                    key_metadata: {key_id: $key_id, type: "ECDSA", bits: 256},
                    ca_expiration: {type: "Duration", duration: "3650d"},
                    profile_id: $profile_id,
                    engine_id: "golang-1",
                    metadata: {sample: true, type: "imported-root"}
                }')")
            CA_RC=$?
            if [ ${CA_RC} -ne 0 ]; then
                warn "could not create imported root CA (may already exist): ${CA_RESP}"
                IMPORTED_CA_ID="sample-imported-root-ca"
            else
                IMPORTED_CA_ID=$(echo "${CA_RESP}" | jq -r '.id // empty')
                log "Successfully imported key and created Root CA: ${IMPORTED_CA_ID}"
            fi
        fi
    fi
fi

# ------------------------------------------------------------------------- #
# Step 3: create the Generated Root CA
# ------------------------------------------------------------------------- #
log "Creating Generated Root CA..."

GENERATED_CA_ID=""
if [ -n "${GENERATED_ROOT_CA_PROFILE_ID}" ]; then
    CA_RESP=$(api_call -X POST "${CA_URL}/v1/cas" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg profile_id "${GENERATED_ROOT_CA_PROFILE_ID}" '{
            id: "sample-generated-root-ca",
            subject: {
                common_name: "Sample Generated Root CA",
                organization: "LamassuIoT Sample",
                organization_unit: "Development",
                country: "ES",
                state: "Gipuzkoa",
                locality: "Arrasate"
            },
            key_metadata: {type: "ECDSA", bits: 256},
            ca_expiration: {type: "Duration", duration: "3650d"},
            profile_id: $profile_id,
            metadata: {sample: true, type: "generated-root"}
        }')")
    CA_RC=$?
    if [ ${CA_RC} -ne 0 ]; then
        warn "could not create generated root CA (may already exist): ${CA_RESP}"
        GENERATED_CA_ID="sample-generated-root-ca"
    else
        GENERATED_CA_ID=$(echo "${CA_RESP}" | jq -r '.id // empty')
        log "Created Generated Root CA: ${GENERATED_CA_ID}"
    fi
fi

# ------------------------------------------------------------------------- #
# Step 4: certificate issuance profiles (server / client / device)
# ------------------------------------------------------------------------- #
log "Creating certificate issuance profiles..."

SERVER_PROFILE_ID=$(create_issuance_profile \
    "Server Certificates" "Profile for issuing server certificates" \
    "365d" false '["DigitalSignature","KeyEncipherment"]' '["ServerAuth"]' true)

CLIENT_PROFILE_ID=$(create_issuance_profile \
    "Client Certificates" "Profile for issuing client certificates" \
    "365d" false '["DigitalSignature"]' '["ClientAuth"]' true)

DEVICE_PROFILE_ID=$(create_issuance_profile \
    "Device Certificates" "Profile for issuing device certificates" \
    "365d" false '["DigitalSignature","KeyEncipherment"]' '["ClientAuth","ServerAuth"]' true)

# ------------------------------------------------------------------------- #
# Step 5: issue 4 sample certificates from each root CA
# ------------------------------------------------------------------------- #
issue_sample_certificates() {
    local ca_id="$1" ca_type="$2"
    [ -n "${ca_id}" ] || return 0
    [ -n "${SERVER_PROFILE_ID}" ] && [ -n "${CLIENT_PROFILE_ID}" ] && [ -n "${DEVICE_PROFILE_ID}" ] || {
        warn "skipping certificate issuance for CA ${ca_id}: missing profile(s)"
        return 0
    }

    log "Issuing certificates from ${ca_type} Root CA: ${ca_id}"

    local specs=(
        "device-cert-${ca_type}-001|device|device001.${ca_type}.example.com"
        "device-cert-${ca_type}-002|device|device002.${ca_type}.example.com"
        "server-cert-${ca_type}|server|api.${ca_type}.example.com,www.${ca_type}.example.com"
        "client-cert-${ca_type}|client|"
    )

    local spec cn cert_type dns_csv profile_id csr serial
    for spec in "${specs[@]}"; do
        IFS='|' read -r cn cert_type dns_csv <<<"${spec}"

        case "${cert_type}" in
            server) profile_id="${SERVER_PROFILE_ID}" ;;
            client) profile_id="${CLIENT_PROFILE_ID}" ;;
            device) profile_id="${DEVICE_PROFILE_ID}" ;;
        esac

        local dns=()
        if [ -n "${dns_csv}" ]; then
            IFS=',' read -r -a dns <<<"${dns_csv}"
        fi

        csr=$(csr_b64 "${cn}" "LamassuIoT Sample" "${WORKDIR}/${cn}.key" "${dns[@]}")
        serial=$(sign_certificate "${ca_id}" "${profile_id}" "${csr}")
        if [ -z "${serial}" ]; then
            warn "could not sign certificate ${cn}"
            continue
        fi
        log "Successfully issued certificate: ${cn} (Serial: ${serial})"
    done
}

issue_sample_certificates "${IMPORTED_CA_ID}" "imported"
issue_sample_certificates "${GENERATED_CA_ID}" "generated"

# ------------------------------------------------------------------------- #
# Step 6: sample DMS
# ------------------------------------------------------------------------- #
SAMPLE_DMS_ID="sample-dms-01"
log "Creating sample DMS: ${SAMPLE_DMS_ID}"

DMS_RESP=$(api_call -X POST "${DMS_URL}/v1/dms" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg enrollment_ca "${IMPORTED_CA_ID}" '{
        id: "sample-dms-01",
        name: "Sample DMS",
        metadata: {description: "Sample DMS for testing", sample: true},
        settings: {
            server_keygen_settings: {enabled: false, key: {type: "RSA", bits: 2048}},
            enrollment_settings: {
                protocol: "EST_RFC7030",
                est_rfc7030_settings: {
                    auth_mode: "CLIENT_CERTIFICATE",
                    client_certificate_settings: {validation_cas: [], chain_level_validation: -1, allow_expired: false},
                    external_webhook_settings: {}
                },
                device_provisioning_profile: {
                    icon: "Laptop",
                    icon_color: "#0066CC",
                    metadata: {sample: true},
                    tags: ["sample", "test"]
                },
                enrollment_ca: $enrollment_ca,
                enable_replaceable_enrollment: false,
                registration_mode: "JITP",
                verify_csr_signature: false
            },
            reenrollment_settings: {
                est_rfc7030_settings: {
                    auth_mode: "CLIENT_CERTIFICATE",
                    client_certificate_settings: {validation_cas: [], chain_level_validation: -1, allow_expired: false},
                    external_webhook_settings: {}
                },
                additional_validation_cas: [],
                revoke_on_reenrollment: false
            },
            ca_distribution_settings: {
                include_system_ca: true,
                include_enrollment_ca: true,
                managed_cas: []
            }
        }
    }')")
DMS_RC=$?

SAMPLE_DMS_USED_ID="sample-dms-01"
if [ ${DMS_RC} -ne 0 ]; then
    warn "could not create DMS (may already exist): ${DMS_RESP}"
else
    SAMPLE_DMS_USED_ID=$(echo "${DMS_RESP}" | jq -r '.id // "sample-dms-01"')
    log "Created sample DMS: ${SAMPLE_DMS_USED_ID}"
fi

# ------------------------------------------------------------------------- #
# Step 7: sample devices
#
# id|icon|iconColor|tags(csv)|location|type|manufacturer|firmware
# ------------------------------------------------------------------------- #
SAMPLE_DEVICES=(
    "device-001|Thermometer|#FF6B6B|production,warehouse,sensor|Warehouse A|temperature-sensor|SensorCorp|v2.1.0"
    "device-002|AirVent|#4ECDC4|production,warehouse,sensor|Warehouse A|humidity-sensor|SensorCorp|v2.1.0"
    "device-003|Router|#95E1D3|development,lab,gateway|Lab B|iot-gateway|TechGateway|v1.5.2"
    "device-004|Cpu|#F38181|production,field,controller|Field Site C|plc-controller|IndustrialSys|v3.0.1"
    "device-005|Gauge|#AA96DA|production,field,sensor|Field Site C|pressure-sensor|SensorCorp|v2.0.5"
    "device-006|Zap|#FCBAD3|staging,test,actuator|Test Lab B|electric-actuator|ActuatorTech|v1.2.3"
    "device-007|Camera|#A8D8EA|production,warehouse,camera|Warehouse A|security-camera|VisionTech|v4.2.1"
    "device-008|Activity|#FFD3B6|development,lab,sensor|Lab B|accelerometer|MotionSense|v1.8.0"
    "device-009|Radio|#FFAAA5|production,field,gateway|Field Site D|edge-gateway|EdgeTech|v2.3.4"
    "device-010|Fan|#FF8B94|staging,test,sensor|Test Lab A|airflow-sensor|EnvironmentSys|v1.1.0"
    "device-011|Thermometer|#3498DB|production,warehouse,sensor|Warehouse B|water-level-sensor|FluidSense|v1.9.2"
    "device-012|AirVent|#1ABC9C|production,field,sensor|Field Site A|wind-sensor|WeatherTech|v2.5.0"
    "device-013|Cpu|#9B59B6|development,lab,controller|Lab A|micro-controller|EmbeddedSys|v1.0.5"
    "device-014|Zap|#E74C3C|production,warehouse,actuator|Warehouse B|alarm-system|SecurityPro|v3.2.1"
    "device-015|Gauge|#F39C12|staging,warehouse,sensor|Warehouse C|light-sensor|LuminaTech|v1.7.3"
    "device-016|Router|#16A085|production,field,gateway|Field Site B|wireless-gateway|ConnectTech|v2.8.1"
    "device-017|Activity|#34495E|development,lab,sensor|Lab C|rain-detector|WeatherSense|v1.4.0"
    "device-018|Cpu|#7F8C8D|production,warehouse,controller|Warehouse A|hvac-controller|ClimateTech|v4.1.2"
    "device-019|Radio|#2ECC71|staging,test,gateway|Test Lab C|mesh-gateway|MeshNet|v2.0.0"
    "device-020|Thermometer|#F1C40F|production,field,sensor|Field Site E|solar-irradiance-sensor|SolarTech|v1.6.4"
    "device-021|Camera|#E67E22|production,warehouse,camera|Warehouse C|video-recorder|VisionTech|v5.0.1"
    "device-022|Zap|#C0392B|development,lab,actuator|Lab D|power-switch|ElectroSys|v2.3.0"
    "device-023|Gauge|#ECF0F1|production,field,sensor|Field Site F|snow-depth-sensor|WeatherSense|v1.3.1"
    "device-024|Cpu|#D35400|staging,warehouse,controller|Warehouse D|logistics-controller|LogisticsPro|v3.5.2"
    "device-025|Router|#2980B9|production,field,gateway|Field Site G|ble-gateway|WirelessHub|v1.8.5"
    "device-026|Activity|#16A085|development,lab,sensor|Lab E|vibration-sensor|VibeTech|v2.1.3"
    "device-027|Gauge|#8E44AD|production,warehouse,sensor|Warehouse A|sound-sensor|AudioSense|v1.5.0"
    "device-028|Cpu|#27AE60|staging,test,controller|Test Lab D|display-controller|DisplayTech|v2.9.1"
    "device-029|Gauge|#2ECC71|production,field,sensor|Field Site H|battery-monitor|PowerSense|v1.2.7"
    "device-030|Radio|#E84393|production,warehouse,gateway|Warehouse B|zigbee-gateway|ZigTech|v3.1.0"
    "device-031|Activity|#00B894|development,lab,sensor|Lab F|gps-tracker|NaviTech|v2.4.2"
    "device-032|Zap|#636E72|staging,warehouse,actuator|Warehouse E|smart-lock|SecureTech|v4.0.3"
    "device-033|Cpu|#B2BEC3|production,field,controller|Field Site I|edge-server|EdgeCompute|v3.7.1"
    "device-034|Activity|#0984E3|production,warehouse,sensor|Warehouse F|motion-detector|SecuritySense|v2.6.0"
    "device-035|Router|#74B9FF|development,lab,gateway|Lab G|cellular-gateway|MobileNet|v1.9.4"
    "device-036|Thermometer|#FD79A8|staging,test,sensor|Test Lab E|location-beacon|BeaconTech|v1.4.5"
    "device-037|Zap|#6C5CE7|production,field,actuator|Field Site J|valve-controller|FlowTech|v2.2.1"
    "device-038|Cpu|#A29BFE|production,warehouse,controller|Warehouse G|inventory-tracker|StockSys|v3.4.0"
    "device-039|Gauge|#FF7675|development,lab,sensor|Lab H|proximity-sensor|RangeTech|v1.6.2"
    "device-040|Camera|#FDCB6E|staging,warehouse,camera|Warehouse H|surveillance-camera|WatchTech|v4.5.1"
    "device-041|Activity|#00CEC9|production,field,sensor|Field Site K|compass-sensor|OrientTech|v1.3.6"
    "device-042|Radio|#FD79A8|production,warehouse,gateway|Warehouse I|lora-gateway|LoRaNet|v2.7.0"
    "device-043|Cpu|#55EFC4|development,lab,controller|Lab I|motor-controller|MotionDrive|v3.0.5"
    "device-044|Zap|#FF6348|staging,test,actuator|Test Lab F|notification-device|AlertSys|v2.1.4"
    "device-045|Gauge|#2D3436|production,field,sensor|Field Site L|distance-sensor|RangeFinder|v1.7.8"
    "device-046|Activity|#DFE6E9|production,warehouse,sensor|Warehouse J|rotation-sensor|SpinTech|v2.0.2"
    "device-047|Router|#A29BFE|development,lab,gateway|Lab J|mqtt-gateway|MQTTHub|v3.2.7"
    "device-048|Cpu|#00B894|staging,warehouse,controller|Warehouse K|analytics-device|DataTech|v4.1.0"
    "device-049|Zap|#FDCB6E|production,field,actuator|Field Site M|relay-switch|SwitchTech|v1.5.9"
    "device-050|Fan|#6C5CE7|production,warehouse,sensor|Warehouse L|time-sync-device|ChronoTech|v2.8.3"
)

log "Creating sample devices..."

create_device() {
    local id="$1" icon="$2" color="$3" tags_csv="$4" location="$5" type="$6" manufacturer="$7" firmware="$8"
    local tags_json body resp rc

    tags_json=$(printf '%s' "${tags_csv}" | jq -R -c 'split(",")')

    body=$(jq -n \
        --arg id "$id" \
        --arg icon "$icon" \
        --arg color "$color" \
        --argjson tags "$tags_json" \
        --arg location "$location" \
        --arg type "$type" \
        --arg manufacturer "$manufacturer" \
        --arg firmware "$firmware" \
        --arg dms_id "$SAMPLE_DMS_USED_ID" \
        '{
            id: $id,
            tags: $tags,
            icon: $icon,
            icon_color: $color,
            metadata: {location: $location, type: $type, manufacturer: $manufacturer, firmware: $firmware, sample: true},
            dms_id: $dms_id
        }')

    resp=$(api_call -X POST "${DEV_URL}/v1/devices" -H 'Content-Type: application/json' -d "${body}")
    rc=$?
    if [ ${rc} -ne 0 ]; then
        warn "could not create device ${id} (may already exist): ${resp}"
    else
        log "Created sample device: ${id}"
    fi
}

for entry in "${SAMPLE_DEVICES[@]}"; do
    IFS='|' read -r d_id d_icon d_color d_tags d_location d_type d_manufacturer d_firmware <<<"${entry}"
    create_device "${d_id}" "${d_icon}" "${d_color}" "${d_tags}" "${d_location}" "${d_type}" "${d_manufacturer}" "${d_firmware}"
done

# ------------------------------------------------------------------------- #
# Step 8: enroll the first 10 devices (issue + bind a certificate)
# ------------------------------------------------------------------------- #
if [ -n "${IMPORTED_CA_ID}" ] && [ -n "${DEVICE_PROFILE_ID}" ]; then
    log "Enrolling 10 sample devices with certificates..."
    for entry in "${SAMPLE_DEVICES[@]:0:10}"; do
        IFS='|' read -r d_id _ _ _ _ _ _ _ <<<"${entry}"
        log "Enrolling device: ${d_id}"

        csr=$(csr_b64 "${d_id}" "LamassuIoT Sample Devices" "${WORKDIR}/${d_id}.key")
        serial=$(sign_certificate "${IMPORTED_CA_ID}" "${DEVICE_PROFILE_ID}" "${csr}")
        if [ -z "${serial}" ]; then
            warn "could not sign certificate for device ${d_id}"
            continue
        fi

        bind_resp=$(api_call -X POST "${DMS_URL}/v1/dms/bind-identity" \
            -H 'Content-Type: application/json' \
            -d "$(jq -n --arg device_id "${d_id}" --arg serial "${serial}" '{
                device_id: $device_id,
                certificate_serial_number: $serial,
                bind_mode: "PROVISIONED"
            }')")
        bind_rc=$?
        if [ ${bind_rc} -ne 0 ]; then
            warn "could not bind certificate to device ${d_id}: ${bind_resp}"
            continue
        fi
        log "Successfully enrolled device ${d_id} with certificate (Serial: ${serial})"
    done
else
    warn "skipping device enrollment: missing imported CA or device profile"
fi

log "Sample data population completed"
log "Workdir (keys/CSRs): ${WORKDIR}"
