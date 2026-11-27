#!/usr/bin/env bash
# Configures every GitHub Actions secret and variable the pipeline needs, using the
# GitHub CLI (https://cli.github.com, run `gh auth login` once first).
#
#   scripts/setup-github.sh [--repo owner/name] [--key ~/.ssh/autodeploy_key] [--dry-run]
#
# Values are taken from environment variables when set (non-interactive use),
# otherwise you are prompted. Secret values are sent over stdin, never as arguments.
#
#   Secrets:    AWS_ACCESS_KEY_ID  AWS_SECRET_ACCESS_KEY  GRAFANA_ADMIN_PASSWORD
#               SSH_PRIVATE_KEY    SSH_PUBLIC_KEY          (the last two come from the key file)
#   Variables:  AWS_REGION  TF_STATE_BUCKET  EC2_INSTANCE_TYPE  DEPLOY_TO_AWS
set -euo pipefail

REPO=""
KEY_PATH="$HOME/.ssh/autodeploy_key"
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while (($# > 0)); do
  case "$1" in
    --repo) REPO="${2:?--repo needs owner/name}"; shift 2 ;;
    --key) KEY_PATH="${2:?--key needs a path}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h | --help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if ! $DRY_RUN; then
  command -v gh >/dev/null 2>&1 || { echo "GitHub CLI (gh) not found: https://cli.github.com" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Not logged in. Run: gh auth login" >&2; exit 1; }
  if [[ -z "$REPO" ]]; then
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  fi
fi
if [[ -z "$REPO" ]]; then
  echo "Could not detect the repository. Pass --repo owner/name." >&2
  exit 1
fi

# ask <VAR> <prompt> [default] [secret]  - uses $VAR when already exported
ask() {
  local var="$1" prompt="$2" default="${3:-}" secret="${4:-}" value="${!1:-}"
  if [[ -z "$value" ]]; then
    if [[ "$secret" == "secret" ]]; then
      read -r -s -p "${prompt}: " value
      echo
    else
      read -r -p "${prompt}${default:+ [${default}]}: " value
    fi
    value="${value:-$default}"
  fi
  printf -v "$var" '%s' "$value"
}

set_secret() { # set_secret <NAME> <value>
  if $DRY_RUN; then
    echo "[dry-run] gh secret set $1 --repo $REPO  (value hidden)"
  else
    printf '%s' "$2" | gh secret set "$1" --repo "$REPO" >/dev/null
    echo "  secret   $1"
  fi
}

set_variable() { # set_variable <NAME> <value>
  if $DRY_RUN; then
    echo "[dry-run] gh variable set $1 --repo $REPO  (value: $2)"
  else
    printf '%s' "$2" | gh variable set "$1" --repo "$REPO" >/dev/null
    echo "  variable $1 = $2"
  fi
}

echo "Configuring GitHub repository: ${REPO}"
echo

# --- SSH key pair -----------------------------------------------------------
if [[ ! -f "$KEY_PATH" ]]; then
  echo "No SSH key at ${KEY_PATH} - generating one."
  "$SCRIPT_DIR/generate-ssh-key.sh" "$KEY_PATH" >/dev/null
fi
SSH_PRIVATE_KEY="$(cat "$KEY_PATH")"
SSH_PUBLIC_KEY="$(cat "${KEY_PATH}.pub")"

# --- values -----------------------------------------------------------------
ask AWS_ACCESS_KEY_ID "AWS access key ID"
ask AWS_SECRET_ACCESS_KEY "AWS secret access key" "" secret
ask AWS_REGION "AWS region" "ap-south-1"
ask TF_STATE_BUCKET "Terraform state bucket (create it with scripts/bootstrap-backend.sh)"
ask EC2_INSTANCE_TYPE "EC2 instance type" "t3.small"

GENERATED_PASSWORD=false
if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
  read -r -s -p "Grafana admin password (min 8 chars, Enter = generate one): " GRAFANA_ADMIN_PASSWORD
  echo
  if [[ -z "$GRAFANA_ADMIN_PASSWORD" ]]; then
    GRAFANA_ADMIN_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
    GENERATED_PASSWORD=true
  fi
fi
if ((${#GRAFANA_ADMIN_PASSWORD} < 8)) || [[ "$GRAFANA_ADMIN_PASSWORD" == *"'"* ]]; then
  echo "Grafana password must be at least 8 characters and must not contain a single quote." >&2
  exit 1
fi
for required in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TF_STATE_BUCKET; do
  if [[ -z "${!required}" ]]; then
    echo "${required} must not be empty." >&2
    exit 1
  fi
done

# --- push to GitHub ---------------------------------------------------------
echo
set_secret AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
set_secret AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
set_secret GRAFANA_ADMIN_PASSWORD "$GRAFANA_ADMIN_PASSWORD"
set_secret SSH_PRIVATE_KEY "$SSH_PRIVATE_KEY"
set_secret SSH_PUBLIC_KEY "$SSH_PUBLIC_KEY"
set_variable AWS_REGION "$AWS_REGION"
set_variable TF_STATE_BUCKET "$TF_STATE_BUCKET"
set_variable EC2_INSTANCE_TYPE "$EC2_INSTANCE_TYPE"
set_variable DEPLOY_TO_AWS "true"

echo
echo "Done. Push to the main branch (or re-run the 'CI/CD' workflow) to deploy."
if $GENERATED_PASSWORD; then
  echo "Generated Grafana admin password (shown once, user 'admin'): ${GRAFANA_ADMIN_PASSWORD}"
fi
