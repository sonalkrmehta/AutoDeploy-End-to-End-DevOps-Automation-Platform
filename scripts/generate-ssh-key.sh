#!/usr/bin/env bash
# Creates the SSH key pair the pipeline uses: Terraform installs the public key on
# the EC2 server, Ansible logs in with the private key.
#
#   scripts/generate-ssh-key.sh [path]      (default: ~/.ssh/autodeploy_key)
set -euo pipefail

KEY_PATH="${1:-$HOME/.ssh/autodeploy_key}"

if [[ -e "$KEY_PATH" ]]; then
  echo "Key already exists, not overwriting: ${KEY_PATH}"
else
  mkdir -p "$(dirname "$KEY_PATH")"
  ssh-keygen -t ed25519 -N "" -C "autodeploy" -f "$KEY_PATH" >/dev/null
  echo "Created ${KEY_PATH} and ${KEY_PATH}.pub"
fi

cat <<EOF

Public key  (GitHub secret SSH_PUBLIC_KEY / Terraform variable ssh_public_key):
$(cat "${KEY_PATH}.pub")

Private key (GitHub secret SSH_PRIVATE_KEY):
  ${KEY_PATH}
  Keep it secret and never commit it. 'scripts/setup-github.sh' uploads both keys for you.
EOF
