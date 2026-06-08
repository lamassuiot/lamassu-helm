#!/bin/bash

set -euo pipefail

NAMESPACE="lamassu-dev"
KUBE_CONTEXT=""
kubectl="kubectl"
helm="helm"

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NOCOLOR='\033[0m'

function usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo " -h, --help       Display this help message"
    echo " -c, --context    Kubernetes context to use"
    echo " -ns, --namespace Namespace to nuke (default: lamassu-dev)"
    echo " -y, --yes        Skip confirmation prompt"
}

YES=false

while [ $# -gt 0 ]; do
    case $1 in
    -h | --help)
        usage
        exit 0
        ;;
    -c | --context*)
        KUBE_CONTEXT="${2:-${1#*=}}"
        shift
        ;;
    -ns | --namespace*)
        NAMESPACE="${2:-${1#*=}}"
        shift
        ;;
    -y | --yes)
        YES=true
        ;;
    *)
        echo -e "${RED}Invalid option: $1${NOCOLOR}" >&2
        usage
        exit 1
        ;;
    esac
    shift
done

if [ -n "$KUBE_CONTEXT" ]; then
    kubectl="kubectl --context $KUBE_CONTEXT"
    helm="helm --kube-context $KUBE_CONTEXT"
fi

if [ "$YES" = false ]; then
    echo -e "${RED}WARNING: This will permanently delete all Helm releases, PVCs, and PVs in namespace '${NAMESPACE}'.${NOCOLOR}"
    echo -n "Type the namespace to confirm: "
    read confirmation
    if [ "$confirmation" != "$NAMESPACE" ]; then
        echo -e "${ORANGE}Aborted.${NOCOLOR}"
        exit 0
    fi
fi

echo -e "\n${ORANGE}=== Nuking namespace: ${NAMESPACE} ===${NOCOLOR}"

# Uninstall all Helm releases in the namespace
echo -e "\n${ORANGE}Uninstalling Helm releases...${NOCOLOR}"
releases=$($helm list -n "$NAMESPACE" -q 2>/dev/null || true)
if [ -n "$releases" ]; then
    for release in $releases; do
        echo "  Uninstalling: $release"
        $helm uninstall "$release" -n "$NAMESPACE" --wait 2>/dev/null || true
    done
else
    echo "  No Helm releases found."
fi

# Delete all PVCs in the namespace (triggers PV reclaim for Delete policy)
echo -e "\n${ORANGE}Deleting PVCs...${NOCOLOR}"
pvcs=$($kubectl get pvc -n "$NAMESPACE" -o name 2>/dev/null || true)
if [ -n "$pvcs" ]; then
    $kubectl delete pvc --all -n "$NAMESPACE" --wait=true
    echo -e "  ${GREEN}PVCs deleted.${NOCOLOR}"
else
    echo "  No PVCs found."
fi

# Delete PVs that were bound to this namespace (Retain policy leaves them Released)
echo -e "\n${ORANGE}Deleting released/failed PVs previously bound to ${NAMESPACE}...${NOCOLOR}"
released_pvs=$($kubectl get pv -o json 2>/dev/null \
    | jq -r ".items[] | select(.spec.claimRef.namespace==\"${NAMESPACE}\") | .metadata.name" 2>/dev/null || true)
if [ -n "$released_pvs" ]; then
    for pv in $released_pvs; do
        echo "  Deleting PV: $pv"
        $kubectl delete pv "$pv" 2>/dev/null || true
    done
else
    echo "  No lingering PVs found."
fi

# Delete the namespace itself
echo -e "\n${ORANGE}Deleting namespace ${NAMESPACE}...${NOCOLOR}"
if $kubectl get ns "$NAMESPACE" &>/dev/null; then
    $kubectl delete ns "$NAMESPACE" --wait=true
    echo -e "  ${GREEN}Namespace deleted.${NOCOLOR}"
else
    echo "  Namespace not found, nothing to delete."
fi

echo -e "\n${GREEN}=== Done. ${NAMESPACE} has been nuked. ===${NOCOLOR}"