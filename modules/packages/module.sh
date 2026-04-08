# shellcheck shell=bash
# modules/packages/module.sh -- Package management module.
# Source this file; do not execute it directly.
#
# Handles: system update, repos (RPM Fusion, Brave, HashiCorp, Kubernetes,
#          ROCm), codec swaps, RPM packages, Flatpak apps, and post-install
#          hooks (KVM, Firefox Wayland, ProtonVPN, Yubikey).
#
# Package lists live in packages.conf (single source of truth).
# Assumes core libs sourced. pkg_install(), find_fedora_version(),
# REPO_ROOT, MODULE_DIR, PROFILE_* vars available.

# ---------------------------------------------------------------------------
# Version pins (override via env vars for testing)
# ---------------------------------------------------------------------------

_PROTON_RPM="${PROTON_RPM:-protonvpn-stable-release-1.0.1-2.noarch.rpm}"
_K8S_VERSION="${K8S_VERSION:-v1.34}"
_ROCM_RHEL_VER="${ROCM_RHEL_VER:-9.5}"

# ---------------------------------------------------------------------------
# Config parser
# ---------------------------------------------------------------------------

declare -gA _PKG_SECTIONS=()

# _pkg_load_conf
# Reads packages.conf into _PKG_SECTIONS: section name -> space-delimited list.
_pkg_load_conf() {
    local file="${MODULE_DIR}/packages.conf"
    [[ -f "$file" ]] || die "packages.conf not found at $file"

    _PKG_SECTIONS=()
    local section="" line

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        [[ -z "$section" ]] && continue
        _PKG_SECTIONS["$section"]+="${_PKG_SECTIONS["$section"]:+ }${line}"
    done < "$file"
}

# ---------------------------------------------------------------------------
# Package list builders
# ---------------------------------------------------------------------------

# _pkg_get_rpm_targets
# Emits one RPM package name per line based on profile toggles.
# Qualifier after ':' gates inclusion: gtk/qt match desktop_toolkit,
# anything else checks PROFILE_PACKAGES_<QUALIFIER> boolean.
_pkg_get_rpm_targets() {
    local section qualifier
    for section in "${!_PKG_SECTIONS[@]}"; do
        [[ "$section" == flatpak:* ]] && continue

        # sway-extra: only on non-Sway-Spin (unconditional — core system premise)
        [[ "$section" == "sway-extra" && "$_PKG_SWAY_SPIN" == "true" ]] && continue

        qualifier="${section#*:}"
        [[ "$qualifier" == "$section" ]] && qualifier=""

        case "$qualifier" in
            "")     ;;
            gtk)    [[ "$_PKG_DESKTOP_TOOLKIT" == "gtk" ]] || continue ;;
            qt)     [[ "$_PKG_DESKTOP_TOOLKIT" == "qt" ]] || continue ;;
            *)      local toggle_var="PROFILE_PACKAGES_${qualifier^^}"
                    [[ "${!toggle_var:-false}" == "true" ]] || continue ;;
        esac

        local -a items
        read -ra items <<< "${_PKG_SECTIONS[$section]}"
        printf '%s\n' "${items[@]}"
    done
}

# _pkg_get_flatpak_targets
# Emits one Flatpak app ID per line from flatpak:* sections.
_pkg_get_flatpak_targets() {
    local section
    for section in "${!_PKG_SECTIONS[@]}"; do
        [[ "$section" == flatpak:* ]] || continue
        local -a items
        read -ra items <<< "${_PKG_SECTIONS[$section]}"
        printf '%s\n' "${items[@]}"
    done
}

# _pkg_check_missing_rpms
# Reads package names from stdin, emits only those not installed.
_pkg_check_missing_rpms() {
    local pkg
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        rpm -q "$pkg" &>/dev/null || echo "$pkg"
    done
}

# ---------------------------------------------------------------------------
# Flatpak helper
# ---------------------------------------------------------------------------

_pkg_flatpak_install() {
    flatpak install --user -y flathub "$1" || die "Failed to install Flatpak: $1"
    mkdir -p "$(dirname "$FLATPAK_MANIFEST")"
    grep -qFx "$1" "$FLATPAK_MANIFEST" 2>/dev/null || echo "$1" >> "$FLATPAK_MANIFEST"
}

# ---------------------------------------------------------------------------
# Repo setup helpers (each under 30 lines, called from apply)
# ---------------------------------------------------------------------------

_pkg_setup_rpm_fusion() {
    [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]] || return 0
    rpm -q rpmfusion-free-release &>/dev/null && return 0

    info "Configuring RPM Fusion repositories..."
    local fedora_ver
    fedora_ver=$(rpm -E %fedora)
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm" \
        || die "Failed to install RPM Fusion repos"
    ok "RPM Fusion configured"
}

_pkg_setup_codec_swaps() {
    [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]] || return 0

    sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 \
        || die "Failed to enable Cisco OpenH264 repo"

    if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
        sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y \
            || die "Failed to swap ffmpeg-free -> ffmpeg"
    fi
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
        sudo dnf swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing -y \
            || die "Failed to swap mesa-va-drivers -> mesa-va-drivers-freeworld"
    fi
    ok "Codecs configured"
}

_pkg_setup_brave_repo() {
    [[ "${_PKG_SECTIONS[browsers]:-}" == *brave-browser* ]] || return 0
    [[ -f /etc/yum.repos.d/brave-browser.repo ]] && return 0

    info "Adding Brave browser repo..."
    sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
        || die "Failed to add Brave repo"
}

_pkg_setup_hashicorp_repo() {
    if [[ ! -f /etc/yum.repos.d/hashicorp.repo ]]; then
        local hashi_ver
        hashi_ver=$(find_fedora_version \
            "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
        if [[ -z "${hashi_ver:-}" ]]; then
            warn "HashiCorp repo unavailable -- terraform will be skipped"
            return 0
        fi
        sudo dnf config-manager addrepo \
            --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
            || die "Failed to add HashiCorp repo"
        sudo sed -i "s/\$releasever/$hashi_ver/g" /etc/yum.repos.d/hashicorp.repo \
            || die "Failed to pin HashiCorp repo version"
        [[ "$hashi_ver" != "$(rpm -E %fedora)" ]] && \
            warn "HashiCorp repo pinned to Fedora $hashi_ver"
        _PKG_HASHICORP_AVAILABLE=true
        return 0
    fi

    # Existing repo -- pin $releasever if still present
    if sudo grep -q '\$releasever' /etc/yum.repos.d/hashicorp.repo; then
        local hashi_ver
        hashi_ver=$(find_fedora_version \
            "https://rpm.releases.hashicorp.com/fedora/{ver}/x86_64/stable/repodata/repomd.xml") || true
        if [[ -n "${hashi_ver:-}" ]]; then
            sudo sed -i "s/\$releasever/$hashi_ver/g" /etc/yum.repos.d/hashicorp.repo \
                || die "Failed to pin HashiCorp repo version"
        else
            warn "HashiCorp repo unavailable -- disabling"
            sudo dnf config-manager setopt hashicorp.enabled=0 \
                || die "Failed to disable HashiCorp repo"
            return 0
        fi
    fi
    _PKG_HASHICORP_AVAILABLE=true
}

_pkg_setup_kubernetes_repo() {
    [[ -f /etc/yum.repos.d/kubernetes.repo ]] && return 0
    cat <<KREPO | sudo tee /etc/yum.repos.d/kubernetes.repo > /dev/null
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${_K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${_K8S_VERSION}/rpm/repodata/repomd.xml.key
KREPO
    sudo chmod 644 /etc/yum.repos.d/kubernetes.repo \
        || die "Failed to write Kubernetes repo"
}

_pkg_setup_devops_repos() {
    [[ "${PROFILE_PACKAGES_DEVOPS:-false}" == "true" ]] || return 0
    _pkg_setup_hashicorp_repo
    _pkg_setup_kubernetes_repo
}

_pkg_setup_rocm_repos() {
    [[ "$_PKG_ROCM_ENABLED" == "true" ]] || return 0
    [[ -f /etc/yum.repos.d/amdgpu.repo ]] && return 0

    info "Configuring ROCm repositories..."
    sudo tee /etc/yum.repos.d/amdgpu.repo > /dev/null <<AMDGPU
[amdgpu]
name=amdgpu
baseurl=https://repo.radeon.com/amdgpu/latest/rhel/${_ROCM_RHEL_VER}/main/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
AMDGPU
    sudo tee /etc/yum.repos.d/rocm.repo > /dev/null <<ROCM
[rocm]
name=ROCm
baseurl=https://repo.radeon.com/rocm/rhel9/${_ROCM_RHEL_VER}/main
enabled=1
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
ROCM
    sudo chmod 644 /etc/yum.repos.d/amdgpu.repo /etc/yum.repos.d/rocm.repo \
        || die "Failed to write ROCm repos"
    ok "ROCm repos configured"
}

# ---------------------------------------------------------------------------
# Post-install helpers (each under 30 lines, called from apply)
# ---------------------------------------------------------------------------

_pkg_apply_firefox_wayland() {
    [[ "${PROFILE_PACKAGES_FIREFOX_WAYLAND:-true}" == "true" ]] || return 0
    [[ "${_PKG_SECTIONS[browsers]:-}" == *firefox* ]] || return 0
    grep -xF 'MOZ_ENABLE_WAYLAND=1' /etc/environment &>/dev/null && return 0

    echo 'MOZ_ENABLE_WAYLAND=1' | sudo tee -a /etc/environment > /dev/null \
        || die "Failed to set MOZ_ENABLE_WAYLAND in /etc/environment"
    ok "MOZ_ENABLE_WAYLAND=1 added to /etc/environment"
}

_pkg_apply_protonvpn() {
    [[ "${PROFILE_PACKAGES_PROTONVPN:-false}" == "true" ]] || return 0
    rpm -q proton-vpn-gtk-app &>/dev/null && { ok "ProtonVPN already installed"; return 0; }

    info "Installing ProtonVPN..."
    require_cmd curl "sudo dnf install -y curl"

    local proton_base="https://repo.protonvpn.com"
    local proton_ver
    proton_ver=$(find_fedora_version \
        "${proton_base}/fedora-{ver}-stable/protonvpn-stable-release/${_PROTON_RPM}") || true

    if [[ -z "${proton_ver:-}" ]]; then
        warn "Could not find a ProtonVPN repo for current Fedora. Skipping."
        return 0
    fi

    sudo dnf install -y \
        "${proton_base}/fedora-${proton_ver}-stable/protonvpn-stable-release/${_PROTON_RPM}" \
        || die "Failed to install ProtonVPN repo"
    pkg_install proton-vpn-gtk-app
    ok "ProtonVPN installed"
}

# Terraform: requires HashiCorp repo; installed separately because the repo
# may be unavailable for the current Fedora release.
_pkg_apply_terraform() {
    [[ "${PROFILE_PACKAGES_DEVOPS:-false}" == "true" ]] || return 0

    if [[ "$_PKG_HASHICORP_AVAILABLE" == "true" ]]; then
        pkg_install terraform
    else
        warn "terraform skipped (HashiCorp repo not available)"
    fi
}

_pkg_apply_flatpaks() {
    [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]] || return 0

    info "Installing Flatpak apps..."
    pkg_install flatpak
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        || die "Failed to add Flathub remote"

    local app_id
    while IFS= read -r app_id; do
        [[ -z "$app_id" ]] && continue
        _pkg_flatpak_install "$app_id"
    done < <(_pkg_get_flatpak_targets)
    ok "Flatpak apps installed"
}

_pkg_apply_kvm() {
    [[ "${PROFILE_PACKAGES_KVM:-false}" == "true" ]] || return 0
    [[ -z "${_PKG_SECTIONS[kvm:kvm]:-}" ]] && return 0

    info "Configuring KVM..."
    sudo usermod -aG libvirt "$(id -un)" \
        || die "Failed to add user to libvirt group"
    sudo systemctl enable --now libvirtd \
        || die "Failed to enable libvirtd"
    ok "KVM configured"
}

_pkg_apply_security_postinstall() {
    [[ "${PROFILE_PACKAGES_SECURITY:-true}" == "true" ]] || return 0
    mkdir -p "$HOME/.config/Yubico"
}

# ---------------------------------------------------------------------------
# Module contract
# ---------------------------------------------------------------------------

packages::init() {
    detect_mode
    _PKG_SWAY_SPIN="$SWAY_SPIN"
    _PKG_DESKTOP_TOOLKIT="${PROFILE_PACKAGES_DESKTOP_TOOLKIT:-qt}"
    _PKG_ROCM_ENABLED="${PROFILE_PACKAGES_ROCM:-false}"
    _PKG_HASHICORP_AVAILABLE=false

    # Validate ROCm against GPU presence
    if [[ "$_PKG_ROCM_ENABLED" == "true" ]]; then
        detect_gpu
        if [[ "$_HAS_DISCRETE_AMD_GPU" != "true" ]]; then
            warn "packages.rocm = true but no discrete AMD GPU detected -- ROCm will be skipped"
            _PKG_ROCM_ENABLED=false
        fi
    fi

    _pkg_load_conf
}

packages::check() {
    # RPM Fusion
    if [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]]; then
        rpm -q rpmfusion-free-release &>/dev/null || return 0
    fi

    # Codec swaps
    if [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]]; then
        if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
            return 0
        fi
        if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            return 0
        fi
    fi

    # RPM packages
    local missing
    missing=$(_pkg_get_rpm_targets | _pkg_check_missing_rpms)
    [[ -n "$missing" ]] && return 0

    # Flatpaks
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        local app_id
        while IFS= read -r app_id; do
            [[ -z "$app_id" ]] && continue
            flatpak list --user --app --columns=application 2>/dev/null \
                | grep -qFx "$app_id" || return 0
        done < <(_pkg_get_flatpak_targets)
    fi

    # ProtonVPN
    if [[ "${PROFILE_PACKAGES_PROTONVPN:-false}" == "true" ]]; then
        rpm -q proton-vpn-gtk-app &>/dev/null || return 0
    fi

    return 1
}

packages::preview() {
    info "[packages] Preview:"

    echo "  Sway Spin: $_PKG_SWAY_SPIN"
    echo "  Desktop toolkit: $_PKG_DESKTOP_TOOLKIT"
    echo "  DNF update: ${PROFILE_PACKAGES_DNF_UPDATE:-true}"
    echo "  RPM Fusion: ${PROFILE_PACKAGES_RPM_FUSION:-true}"
    echo "  Codec swaps: ${PROFILE_PACKAGES_CODEC_SWAPS:-true}"
    echo "  Flatpak: ${PROFILE_PACKAGES_FLATPAK:-true}"
    echo "  CLI tools: ${PROFILE_PACKAGES_CLI_TOOLS:-true}"
    echo "  Security: ${PROFILE_PACKAGES_SECURITY:-true}"
    echo "  ROCm: $_PKG_ROCM_ENABLED"
    echo "  DevOps: ${PROFILE_PACKAGES_DEVOPS:-false}"
    echo "  KVM: ${PROFILE_PACKAGES_KVM:-false}"
    echo "  ProtonVPN: ${PROFILE_PACKAGES_PROTONVPN:-false}"
    echo "  Firefox Wayland: ${PROFILE_PACKAGES_FIREFOX_WAYLAND:-true}"
    echo ""

    # Repos
    if [[ "${PROFILE_PACKAGES_RPM_FUSION:-true}" == "true" ]]; then
        rpm -q rpmfusion-free-release &>/dev/null || echo "  Repos: RPM Fusion  [WILL ADD]"
    fi
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        flatpak remote-list --user 2>/dev/null | grep -q flathub || echo "  Repos: Flathub  [WILL ADD]"
    fi

    # Codec swaps
    if [[ "${PROFILE_PACKAGES_CODEC_SWAPS:-true}" == "true" ]]; then
        if rpm -q ffmpeg-free &>/dev/null && ! rpm -q ffmpeg &>/dev/null; then
            echo "  Codec swap: ffmpeg-free -> ffmpeg  [WILL SWAP]"
        fi
        if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            echo "  Codec swap: mesa-va-drivers -> mesa-va-drivers-freeworld  [WILL SWAP]"
        fi
    fi

    # Missing RPMs
    local missing
    missing=$(_pkg_get_rpm_targets | _pkg_check_missing_rpms)
    if [[ -n "$missing" ]]; then
        echo ""
        echo "  Packages to install:"
        # shellcheck disable=SC2001
        echo "$missing" | sed 's/^/    /'
    else
        echo "  All RPM packages installed."
    fi

    # ProtonVPN
    if [[ "${PROFILE_PACKAGES_PROTONVPN:-false}" == "true" ]]; then
        rpm -q proton-vpn-gtk-app &>/dev/null || echo "  ProtonVPN:  [WILL INSTALL]"
    fi

    # Flatpaks
    if [[ "${PROFILE_PACKAGES_FLATPAK:-true}" == "true" ]]; then
        local missing_flatpaks=()
        local app_id
        while IFS= read -r app_id; do
            [[ -z "$app_id" ]] && continue
            flatpak list --user --app --columns=application 2>/dev/null \
                | grep -qFx "$app_id" || missing_flatpaks+=("$app_id")
        done < <(_pkg_get_flatpak_targets)

        if [[ ${#missing_flatpaks[@]} -gt 0 ]]; then
            echo "  Flatpaks to install:"
            printf '    %s\n' "${missing_flatpaks[@]}"
        fi
    else
        echo "  Flatpaks: disabled  [SKIP]"
    fi
}

packages::apply() {
    preflight_checks

    # System update (toggle: packages.dnf_update)
    if [[ "${PROFILE_PACKAGES_DNF_UPDATE:-true}" == "true" ]]; then
        info "Updating system packages..."
        sudo dnf update -y || die "DNF update failed"
        ok "System updated"
    fi

    # dnf-plugins-core (unconditional -- required for dnf config-manager)
    pkg_install dnf-plugins-core

    # Repos
    _pkg_setup_rpm_fusion
    _pkg_setup_codec_swaps
    _pkg_setup_brave_repo
    _pkg_setup_devops_repos
    _pkg_setup_rocm_repos

    # Bulk RPM install
    local -a all_rpms
    mapfile -t all_rpms < <(_pkg_get_rpm_targets)
    if [[ ${#all_rpms[@]} -gt 0 ]]; then
        info "Installing RPM packages..."
        pkg_install "${all_rpms[@]}"
        ok "RPM packages installed"
    fi

    # Post-install
    _pkg_apply_terraform
    _pkg_apply_firefox_wayland
    _pkg_apply_protonvpn
    _pkg_apply_flatpaks
    _pkg_apply_kvm
    _pkg_apply_security_postinstall

    ok "Packages complete"
}

packages::status() {
    local rpm_count=0 flatpak_count=0
    [[ -f "$PKG_MANIFEST" ]] && rpm_count=$(wc -l < "$PKG_MANIFEST")
    [[ -f "$FLATPAK_MANIFEST" ]] && flatpak_count=$(wc -l < "$FLATPAK_MANIFEST")
    echo "packages: ${rpm_count} RPM + ${flatpak_count} Flatpak managed"
}
