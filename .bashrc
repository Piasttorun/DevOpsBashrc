#!/usr/bin/env bash
# =============================================================================
# DevOps .bashrc — Bootstrap & Update Script
# =============================================================================
# Installs if missing, updates if present:
#   System packages, Python, Java, Go, Node.js, Docker, Kubernetes (kubectl,
#   helm, k9s, kind, minikube), Terraform, Ansible, AWS CLI, Azure CLI,
#   GCloud CLI, Vault, Packer, Vagrant, jq, yq, shellcheck, hadolint, trivy,
#   lazydocker, stern, kubectx/kubens, k6, grpcurl
#
# Targets: Ubuntu/Debian. For RHEL/Fedora, swap apt blocks with dnf/yum.
# Usage:  source ~/.bashrc   (runs once per new shell; idempotent)
# =============================================================================

# ---------- guard: only run in interactive shells -------------------------
[[ $- != *i* ]] && return

# ---------- config --------------------------------------------------------
export DEVOPS_BOOTSTRAP_LOG="${HOME}/.devops_bootstrap.log"
DEVOPS_BOOTSTRAP_LOCK="/tmp/.devops_bootstrap_$(id -u).lock"
GOLANG_VERSION="1.22.4"
NODE_MAJOR=20
JAVA_VERSION="21"

# ---------- colours for output --------------------------------------------
_info()  { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
_ok()    { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
_warn()  { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
_err()   { printf '\e[1;31m[ ERR]\e[0m  %s\n' "$*"; }

# ---------- helpers -------------------------------------------------------
_cmd_exists()  { command -v "$1" &>/dev/null; }
_need_sudo()   { [[ $EUID -ne 0 ]] && echo "sudo" || echo ""; }
SUDO=$(_need_sudo)

_apt_install() {
    for pkg in "$@"; do
        if dpkg -s "$pkg" &>/dev/null; then
            _ok "$pkg already installed"
        else
            _info "Installing $pkg …"
            $SUDO apt-get install -y "$pkg" >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 \
                && _ok "$pkg installed" || _err "$pkg failed"
        fi
    done
}

# ---------- single-run lock (per shell session) ---------------------------
# Prevents re-running the heavy install loop every time you source .bashrc.
# Delete the lock file to force a re-run: rm /tmp/.devops_bootstrap_*.lock
if [[ -f "$DEVOPS_BOOTSTRAP_LOCK" ]]; then
    # Skip installs, jump to aliases/env at bottom
    _SKIP_INSTALL=true
else
    _SKIP_INSTALL=false
fi

if [[ "$_SKIP_INSTALL" == "false" ]]; then

touch "$DEVOPS_BOOTSTRAP_LOCK"
_info "DevOps bootstrap starting — log at $DEVOPS_BOOTSTRAP_LOG"
echo "--- $(date) ---" >> "$DEVOPS_BOOTSTRAP_LOG"

# =========================================================================
# 1. SYSTEM UPDATE & CORE PACKAGES
# =========================================================================
_info "Updating package lists …"
$SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
_info "Upgrading installed packages …"
$SUDO apt-get upgrade -y -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1

_apt_install \
    build-essential gcc g++ make cmake \
    curl wget gnupg2 ca-certificates lsb-release \
    apt-transport-https software-properties-common \
    git git-lfs unzip zip tar bzip2 xz-utils \
    tree htop tmux screen vim nano \
    net-tools dnsutils iputils-ping traceroute nmap socat netcat-openbsd \
    openssh-client sshpass \
    jq bash-completion \
    libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    python3-pip python3-venv \
    shellcheck

# =========================================================================
# 2. PYTHON (system python3 + pipx for isolated CLI tools)
# =========================================================================
_info "Configuring Python …"
_apt_install python3 python3-pip python3-venv pipx
pipx ensurepath >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1

# Common Python DevOps tools via pipx (isolated)
for tool in ansible ansible-lint yamllint pre-commit black flake8 cookiecutter; do
    if _cmd_exists "$tool"; then
        _info "Updating $tool …"
        pipx upgrade "$tool" >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 && _ok "$tool updated"
    else
        _info "Installing $tool via pipx …"
        pipx install "$tool" >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 && _ok "$tool installed"
    fi
done

# =========================================================================
# 3. JAVA (Eclipse Temurin / Adoptium JDK)
# =========================================================================
if _cmd_exists java && java -version 2>&1 | grep -q "version \"${JAVA_VERSION}"; then
    _ok "Java ${JAVA_VERSION} present"
else
    _info "Installing Eclipse Temurin JDK ${JAVA_VERSION} …"
    $SUDO mkdir -p /etc/apt/keyrings
    wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | $SUDO tee /etc/apt/keyrings/adoptium.asc > /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb \
        $(lsb_release -cs) main" | $SUDO tee /etc/apt/sources.list.d/adoptium.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y "temurin-${JAVA_VERSION}-jdk" >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 \
        && _ok "Java ${JAVA_VERSION} installed" || _err "Java install failed"
fi
# Gradle & Maven
_apt_install maven
if ! _cmd_exists gradle; then
    _info "Installing Gradle via SDKMAN …"
    if ! _cmd_exists sdk; then
        curl -s "https://get.sdkman.io" | bash >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
        source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null
    fi
    sdk install gradle >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 && _ok "Gradle installed"
fi

# =========================================================================
# 4. GO
# =========================================================================
if _cmd_exists go && go version | grep -q "go${GOLANG_VERSION}"; then
    _ok "Go ${GOLANG_VERSION} present"
else
    _info "Installing Go ${GOLANG_VERSION} …"
    wget -q "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    _ok "Go ${GOLANG_VERSION} installed"
fi
export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"

# =========================================================================
# 5. NODE.JS (via NodeSource)
# =========================================================================
if _cmd_exists node && node -v | grep -q "v${NODE_MAJOR}"; then
    _ok "Node.js ${NODE_MAJOR}.x present"
else
    _info "Installing Node.js ${NODE_MAJOR}.x …"
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
        | $SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        | $SUDO tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y nodejs >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1 && _ok "Node.js installed"
fi

# =========================================================================
# 6. DOCKER
# =========================================================================
if _cmd_exists docker; then
    _ok "Docker present ($(docker --version | awk '{print $3}'))"
else
    _info "Installing Docker CE …"
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO usermod -aG docker "$USER" 2>/dev/null
    _ok "Docker installed (re-login for group membership)"
fi

# =========================================================================
# 7. KUBERNETES TOOLS
# =========================================================================

# --- kubectl ---
if _cmd_exists kubectl; then
    _ok "kubectl present"
else
    _info "Installing kubectl …"
    curl -fsSL "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
        -o /tmp/kubectl
    $SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
    _ok "kubectl installed"
fi

# --- helm ---
if _cmd_exists helm; then
    _ok "Helm present"
else
    _info "Installing Helm …"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "Helm installed"
fi

# --- k9s ---
if _cmd_exists k9s; then
    _ok "k9s present"
else
    _info "Installing k9s …"
    K9S_VER=$(curl -sL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_Linux_amd64.tar.gz" -O /tmp/k9s.tar.gz
    tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
    $SUDO mv /tmp/k9s /usr/local/bin/
    rm -f /tmp/k9s.tar.gz
    _ok "k9s installed"
fi

# --- kind ---
if _cmd_exists kind; then
    _ok "kind present"
else
    _info "Installing kind …"
    KIND_VER=$(curl -sL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r '.tag_name')
    curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-amd64"
    $SUDO install -o root -g root -m 0755 /tmp/kind /usr/local/bin/kind
    rm -f /tmp/kind
    _ok "kind installed"
fi

# --- minikube ---
if _cmd_exists minikube; then
    _ok "minikube present"
else
    _info "Installing minikube …"
    curl -fsSLo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    $SUDO install /tmp/minikube /usr/local/bin/minikube
    rm -f /tmp/minikube
    _ok "minikube installed"
fi

# --- kubectx & kubens ---
if _cmd_exists kubectx; then
    _ok "kubectx present"
else
    _info "Installing kubectx/kubens …"
    KCTX_VER=$(curl -sL https://api.github.com/repos/ahmetb/kubectx/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/ahmetb/kubectx/releases/download/${KCTX_VER}/kubectx_${KCTX_VER}_linux_x86_64.tar.gz" -O /tmp/kubectx.tar.gz
    wget -q "https://github.com/ahmetb/kubectx/releases/download/${KCTX_VER}/kubens_${KCTX_VER}_linux_x86_64.tar.gz" -O /tmp/kubens.tar.gz
    tar -xzf /tmp/kubectx.tar.gz -C /tmp kubectx && $SUDO mv /tmp/kubectx /usr/local/bin/
    tar -xzf /tmp/kubens.tar.gz -C /tmp kubens && $SUDO mv /tmp/kubens /usr/local/bin/
    rm -f /tmp/kubectx.tar.gz /tmp/kubens.tar.gz
    _ok "kubectx/kubens installed"
fi

# --- stern (log tailing) ---
if _cmd_exists stern; then
    _ok "stern present"
else
    _info "Installing stern …"
    STERN_VER=$(curl -sL https://api.github.com/repos/stern/stern/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/stern/stern/releases/download/${STERN_VER}/stern_${STERN_VER#v}_linux_amd64.tar.gz" -O /tmp/stern.tar.gz
    tar -xzf /tmp/stern.tar.gz -C /tmp stern && $SUDO mv /tmp/stern /usr/local/bin/
    rm -f /tmp/stern.tar.gz
    _ok "stern installed"
fi

# =========================================================================
# 8. TERRAFORM & HASHICORP TOOLS
# =========================================================================
# Add HashiCorp repo once
if [[ ! -f /etc/apt/sources.list.d/hashicorp.list ]]; then
    _info "Adding HashiCorp repository …"
    wget -qO- https://apt.releases.hashicorp.com/gpg \
        | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
        | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
fi
_apt_install terraform vault packer

# --- tflint ---
if _cmd_exists tflint; then
    _ok "tflint present"
else
    _info "Installing tflint …"
    curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "tflint installed"
fi

# --- terragrunt ---
if _cmd_exists terragrunt; then
    _ok "terragrunt present"
else
    _info "Installing terragrunt …"
    TG_VER=$(curl -sL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/gruntwork-io/terragrunt/releases/download/${TG_VER}/terragrunt_linux_amd64" -O /tmp/terragrunt
    $SUDO install -o root -g root -m 0755 /tmp/terragrunt /usr/local/bin/terragrunt
    rm -f /tmp/terragrunt
    _ok "terragrunt installed"
fi

# =========================================================================
# 9. CLOUD CLIs
# =========================================================================

# --- AWS CLI v2 ---
if _cmd_exists aws; then
    _info "Updating AWS CLI …"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    $SUDO /tmp/aws/install --update >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    rm -rf /tmp/aws /tmp/awscliv2.zip
    _ok "AWS CLI updated"
else
    _info "Installing AWS CLI v2 …"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    $SUDO /tmp/aws/install >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    rm -rf /tmp/aws /tmp/awscliv2.zip
    _ok "AWS CLI installed"
fi

# --- Azure CLI ---
if _cmd_exists az; then
    _ok "Azure CLI present"
else
    _info "Installing Azure CLI …"
    curl -fsSL https://aka.ms/InstallAzureCLIDeb | $SUDO bash >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "Azure CLI installed"
fi

# --- Google Cloud CLI ---
if _cmd_exists gcloud; then
    _ok "gcloud CLI present"
else
    _info "Installing Google Cloud CLI …"
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | $SUDO gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg 2>/dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y google-cloud-cli >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "gcloud installed"
fi

# =========================================================================
# 10. EXTRA DEVOPS UTILITIES
# =========================================================================

# --- yq (YAML processor) ---
if _cmd_exists yq; then
    _ok "yq present"
else
    _info "Installing yq …"
    YQ_VER=$(curl -sL https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VER}/yq_linux_amd64" -O /tmp/yq
    $SUDO install -o root -g root -m 0755 /tmp/yq /usr/local/bin/yq
    rm -f /tmp/yq
    _ok "yq installed"
fi

# --- hadolint (Dockerfile linter) ---
if _cmd_exists hadolint; then
    _ok "hadolint present"
else
    _info "Installing hadolint …"
    HL_VER=$(curl -sL https://api.github.com/repos/hadolint/hadolint/releases/latest | jq -r '.tag_name')
    wget -q "https://github.com/hadolint/hadolint/releases/download/${HL_VER}/hadolint-Linux-x86_64" -O /tmp/hadolint
    $SUDO install -o root -g root -m 0755 /tmp/hadolint /usr/local/bin/hadolint
    rm -f /tmp/hadolint
    _ok "hadolint installed"
fi

# --- trivy (security scanner) ---
if _cmd_exists trivy; then
    _ok "trivy present"
else
    _info "Installing trivy …"
    wget -qO- https://aquasecurity.github.io/trivy-repo/deb/public.key \
        | $SUDO gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
        | $SUDO tee /etc/apt/sources.list.d/trivy.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y trivy >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "trivy installed"
fi

# --- lazydocker ---
if _cmd_exists lazydocker; then
    _ok "lazydocker present"
else
    _info "Installing lazydocker …"
    LD_VER=$(curl -sL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | jq -r '.tag_name' | tr -d 'v')
    wget -q "https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/lazydocker_${LD_VER}_Linux_x86_64.tar.gz" -O /tmp/lazydocker.tar.gz
    tar -xzf /tmp/lazydocker.tar.gz -C /tmp lazydocker
    $SUDO mv /tmp/lazydocker /usr/local/bin/
    rm -f /tmp/lazydocker.tar.gz
    _ok "lazydocker installed"
fi

# --- k6 (load testing) ---
if _cmd_exists k6; then
    _ok "k6 present"
else
    _info "Installing k6 …"
    $SUDO gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
        --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
        | $SUDO tee /etc/apt/sources.list.d/k6.list > /dev/null
    $SUDO apt-get update -qq >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    $SUDO apt-get install -y k6 >> "$DEVOPS_BOOTSTRAP_LOG" 2>&1
    _ok "k6 installed"
fi

# --- grpcurl ---
if _cmd_exists grpcurl; then
    _ok "grpcurl present"
else
    _info "Installing grpcurl …"
    GRPC_VER=$(curl -sL https://api.github.com/repos/fullstorydev/grpcurl/releases/latest | jq -r '.tag_name' | tr -d 'v')
    wget -q "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPC_VER}/grpcurl_${GRPC_VER}_linux_x86_64.tar.gz" -O /tmp/grpcurl.tar.gz
    tar -xzf /tmp/grpcurl.tar.gz -C /tmp grpcurl
    $SUDO mv /tmp/grpcurl /usr/local/bin/
    rm -f /tmp/grpcurl.tar.gz
    _ok "grpcurl installed"
fi

_info "Bootstrap complete!"

fi  # end _SKIP_INSTALL guard

# =========================================================================
# 11. ENVIRONMENT & PATH (always loaded)
# =========================================================================
export JAVA_HOME="/usr/lib/jvm/temurin-${JAVA_VERSION}-jdk-amd64"
export GOPATH="${HOME}/go"
export GOROOT="/usr/local/go"
export PATH="${HOME}/.local/bin:${GOROOT}/bin:${GOPATH}/bin:${JAVA_HOME}/bin:${PATH}"
export EDITOR="vim"
export KUBE_EDITOR="vim"

# =========================================================================
# 12. ALIASES & FUNCTIONS (always loaded)
# =========================================================================

# --- Docker ---
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'
alias dprune='docker system prune -af --volumes'
alias dlogs='docker logs -f'

# --- Kubernetes ---
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgn='kubectl get nodes'
alias kga='kubectl get all'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kdp='kubectl describe pod'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kns='kubens'
alias kctx='kubectx'

# --- Terraform ---
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfv='terraform validate'
alias tff='terraform fmt -recursive'
alias tfs='terraform state'

# --- Git ---
alias g='git'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias gp='git pull --rebase'
alias gd='git diff'
alias gc='git commit'
alias gca='git commit --amend --no-edit'

# --- General ---
alias ll='ls -alFh --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ports='ss -tulnp'
alias myip='curl -s ifconfig.me && echo'
alias reload='source ~/.bashrc'

# --- Functions ---
kshell() {
    # Open a shell in a running pod
    local pod="${1:?Usage: kshell <pod> [namespace]}"
    local ns="${2:-default}"
    kubectl exec -it -n "$ns" "$pod" -- /bin/sh
}

dshell() {
    # Open a shell in a running container
    local ctr="${1:?Usage: dshell <container>}"
    docker exec -it "$ctr" /bin/sh
}

tf_switch() {
    # Quick workspace switch for Terraform
    local ws="${1:?Usage: tf_switch <workspace>}"
    terraform workspace select "$ws" || terraform workspace new "$ws"
}

kubedebug() {
    # Spin up a debug pod with common tools
    kubectl run debug-shell --rm -it --image=nicolaka/netshoot -- /bin/bash
}

decode_secret() {
    # Decode a Kubernetes secret
    local secret="${1:?Usage: decode_secret <secret-name> [namespace]}"
    local ns="${2:-default}"
    kubectl get secret "$secret" -n "$ns" -o json | jq -r '.data | to_entries[] | "\(.key): \(.value | @base64d)"'
}

# =========================================================================
# 13. SHELL COMPLETIONS (always loaded)
# =========================================================================
_cmd_exists kubectl  && source <(kubectl completion bash) 2>/dev/null
_cmd_exists helm     && source <(helm completion bash) 2>/dev/null
_cmd_exists kind     && source <(kind completion bash) 2>/dev/null
_cmd_exists minikube && source <(minikube completion bash) 2>/dev/null
_cmd_exists terraform && complete -C "$(which terraform)" terraform 2>/dev/null
_cmd_exists k9s      && source <(k9s completion bash) 2>/dev/null

# Alias completions for kubectl
complete -o default -F __start_kubectl k 2>/dev/null

# =========================================================================
# 14. PROMPT
# =========================================================================
_kube_ctx() {
    if _cmd_exists kubectl; then
        local ctx
        ctx=$(kubectl config current-context 2>/dev/null)
        [[ -n "$ctx" ]] && echo " ☸ ${ctx}"
    fi
}

_tf_workspace() {
    if [[ -d .terraform ]]; then
        local ws
        ws=$(terraform workspace show 2>/dev/null)
        [[ -n "$ws" && "$ws" != "default" ]] && echo " ⛏ ${ws}"
    fi
}

export PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[33m\]$(_kube_ctx)\[\e[35m\]$(_tf_workspace)\[\e[0m\]\n\$ '

# =========================================================================
_ok "DevOps shell ready. Tools: docker k terraform helm go java python aws az gcloud"
