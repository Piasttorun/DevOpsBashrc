🚀 DevOps Bash Bootstrap

A fully automated, idempotent DevOps environment bootstrap script embedded in .bashrc.

This script installs, configures, and maintains a complete DevOps toolchain on Ubuntu/Debian systems, ensuring your shell is always ready with the latest tools.

-✨ Features

-🔁 Idempotent — safe to run multiple times

-⚡ Auto-bootstrap on shell startup

-🔒 Single-run lock mechanism per session

-📦 Installs & updates automatically

-🧰 Comprehensive DevOps toolkit

-🧠 Smart detection of existing installations

-🧱 What Gets Installed

-🖥️ Core System & Utilities

build-essential, curl, wget, git, vim, tmux, htop
networking tools (nmap, dnsutils, netcat, etc.)
jq, bash-completion, shellcheck

🐍 Python Ecosystem
Python 3 + pip + venv + pipx
Dev tools:
ansible, ansible-lint
yamllint, pre-commit
black, flake8, cookiecutter

☕ Java
Eclipse Temurin JDK (v21)
Maven
Gradle (via SDKMAN)

🐹 Go
Go (v1.22.4)

🟢 Node.js
Node.js (v20 via NodeSource)

🐳 Docker
Docker CE + CLI + Buildx + Compose
Adds user to docker group

☸️ Kubernetes Tooling
kubectl
helm
k9s
kind
minikube
kubectx / kubens
stern

🏗️ Infrastructure as Code
Terraform
Vault
Packer
Terragrunt
TFLint

☁️ Cloud CLIs
AWS CLI v2
Azure CLI
Google Cloud CLI

🔍 DevOps Utilities
yq (YAML processor)
hadolint (Dockerfile linter)
trivy (security scanner)
lazydocker
k6 (load testing)
grpcurl

🚀 Usage

1. Add to your .bashrc
nano ~/.bashrc

Paste the script at the end.

2. Run it
source ~/.bashrc

The bootstrap will:

Install missing tools
Update existing ones
Log everything to:
~/.devops_bootstrap.log
🔒 Execution Control

The script uses a lock file to prevent repeated installs on every shell load:

/tmp/.devops_bootstrap_<uid>.lock
Force re-run:
rm /tmp/.devops_bootstrap_*.lock
source ~/.bashrc
⚙️ Configuration

You can tweak versions at the top of the script:

GOLANG_VERSION="1.22.4"
NODE_MAJOR=20
JAVA_VERSION="21"

🧑‍💻 Developer Experience Enhancements

🔹 Aliases

Shortcuts for common tools:

k      # kubectl
tf     # terraform
d      # docker
g      # git

Examples:

kgp    # kubectl get pods
tfa    # terraform apply
dps    # docker ps (formatted)

🔹 Helper Functions
kshell <pod> [namespace]     # shell into Kubernetes pod
dshell <container>           # shell into Docker container
tf_switch <workspace>        # switch/create Terraform workspace
kubedebug                    # debug pod with net tools
decode_secret <name> [ns]    # decode Kubernetes secret
🔹 Smart Prompt

Your shell prompt includes:

☸️ Current Kubernetes context

⛏️ Terraform workspace

🔹 Auto-completions
Enabled for:
kubectl
helm
terraform
kind
minikube
k9s

📁 Logs

All installation output is logged to:

~/.devops_bootstrap.log

Useful for debugging failed installs.

⚠️ Requirements
Ubuntu / Debian-based system
sudo privileges
Internet access

🧪 Notes
Designed for developer workstations, cloud VMs, and WSL
For RHEL/Fedora, replace apt with dnf/yum
Docker requires re-login after installation for group permissions

🛠️ Troubleshooting
Docker permission denied
newgrp docker
Command not found after install
source ~/.bashrc
Force reinstall everything
rm /tmp/.devops_bootstrap_*.lock
source ~/.bashrc

📌 Summary

This script turns a fresh machine into a fully loaded DevOps workstation in minutes — no manual installs, no drift, no hassle.

🧠 Future Ideas
macOS support (brew)
Plugin system for custom tools
Version pinning via config file
CI validation mode

📄 License
MIT License