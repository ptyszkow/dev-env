FROM registry.fedoraproject.org/fedora:45 AS base

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

RUN dnf -y --setopt=install_weak_deps=False install \
        bash ca-certificates curl-minimal git-core ripgrep fd-find jq diffutils patch \
        findutils procps-ng shadow-utils tar gzip unzip xz zstd file which \
        dotnet-sdk-10.0 clang lld libstdc++-devel gcc-c++ glibc-devel \
        make cmake ninja-build pkgconf-pkg-config openssl-devel \
        rust cargo rustfmt clippy chromium liberation-sans-fonts \
        neovim helix helix-parsers helix-themes \
    && dnf clean all \
    && groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid agent --create-home --shell /bin/bash agent \
    && install -d -o agent -g agent /workspace \
    && ln -s "$(command -v chromium-browser || command -v chromium)" /usr/local/bin/sandbox-chromium \
    && rpm -qa | sort > /usr/local/share/sandbox-rpms.txt

# Share installer setup and version recording across the cached install steps.
RUN <<'SETUP' /bin/bash
cat > /usr/local/share/sandbox-build-common.sh <<'HELPER'
set -euo pipefail

tools_dir=/opt/sandbox
install -d "$tools_dir"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch() { curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$1" -o "$2"; }

record_version() {
    local command=$1 actual
    actual=$("$command" --version)
    if [[ -z $actual ]]; then
        echo "$command --version returned no version" >&2
        return 1
    fi
    printf '%s %s\n' "$command" "$actual" >> "$manifest"
}
HELPER
SETUP

FROM base AS agents

# Changing this argument refreshes this phase while reusing the Fedora base.
ARG REFRESH_AGENTS=cached

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-agents.txt
fetch https://x.ai/cli/install.sh "$tmp/grok.sh"
PATH="$tmp/bin:$PATH" GROK_BIN_DIR="$tmp/bin" bash "$tmp/grok.sh"
install -m 0755 "$(readlink -f "$tmp/bin/grok")" /usr/local/bin/grok
rm -rf ~/.grok
record_version grok
INSTALL

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-agents.txt
fetch https://claude.ai/install.sh "$tmp/claude.sh"
bash "$tmp/claude.sh" latest
claude_root=~/.local/share/claude
claude_binary=$(realpath -e ~/.local/bin/claude)
case $claude_binary in
    "$claude_root"/*)
        mv "$claude_root" "$tools_dir/claude"
        ln -s "$tools_dir/claude/${claude_binary#"$claude_root"/}" /usr/local/bin/claude ;;
    *) install -m 0755 "$claude_binary" /usr/local/bin/claude ;;
esac
record_version claude
INSTALL

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-agents.txt
fetch https://chatgpt.com/codex/install.sh "$tmp/codex.sh"
CODEX_INSTALL_DIR=/usr/local/bin \
    CODEX_HOME="$tools_dir/codex" CODEX_NON_INTERACTIVE=true sh "$tmp/codex.sh"
record_version codex
INSTALL

FROM base AS tools

# Changing this argument refreshes this phase while reusing the Fedora base.
ARG REFRESH_TOOLS=cached

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-tools.txt
fetch https://astral.sh/uv/install.sh "$tmp/uv.sh"
UV_UNMANAGED_INSTALL=/usr/local/bin sh "$tmp/uv.sh"
UV_PYTHON_INSTALL_DIR="$tools_dir/python" UV_PYTHON_BIN_DIR=/usr/local/bin \
    uv --no-cache python install --default
record_version uv
record_version python3
INSTALL

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-tools.txt
fetch https://bun.sh/install "$tmp/bun.sh"
BUN_INSTALL="$tools_dir/bun" bash "$tmp/bun.sh"
ln -s "$tools_dir/bun/bin/bun" /usr/local/bin/bun
ln -s "$tools_dir/bun/bin/bun" /usr/local/bin/bunx
record_version bun
INSTALL

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-tools.txt
fetch https://releases.herdr.dev/core/install.sh "$tmp/herdr-core.sh"
HC_INSTALL_DIR=/usr/local/bin sh "$tmp/herdr-core.sh"
record_version hc
INSTALL

RUN <<'INSTALL' /bin/bash
source /usr/local/share/sandbox-build-common.sh
manifest=/usr/local/share/sandbox-tools.txt
case "$(uname -m)" in
    x86_64) browser_arch=x64 ;;
    aarch64) browser_arch=arm64 ;;
    *) echo "Unsupported architecture for agent-browser: $(uname -m)" >&2; exit 1 ;;
esac
browser_release="https://github.com/vercel-labs/agent-browser/releases/latest/download"
fetch "$browser_release/agent-browser-linux-$browser_arch" "$tmp/agent-browser"
install -m 0755 "$tmp/agent-browser" /usr/local/bin/agent-browser
record_version agent-browser
INSTALL

FROM base AS editors

# Changing this argument refreshes this phase while reusing the Fedora base.
ARG REFRESH_EDITORS=cached

RUN git clone --depth 1 https://github.com/LazyVim/starter.git /opt/sandbox/lazyvim \
    && rm -rf /opt/sandbox/lazyvim/.git

# Roslyn publishes language server packages on NuGet as prereleases.
RUN dotnet tool install roslyn-language-server --prerelease \
        --tool-path /opt/sandbox/dotnet-tools \
    && chmod a+x /opt/sandbox/dotnet-tools/roslyn-language-server \
    && find /opt/sandbox/dotnet-tools/.store -type f -name Microsoft.CodeAnalysis.LanguageServer \
        -exec chmod a+x {} + \
    && ln -s /opt/sandbox/dotnet-tools/roslyn-language-server /usr/local/bin/roslyn-language-server

FROM base AS runtime

# Install audio clients and the language servers shared by both editors.
RUN dnf -y --setopt=install_weak_deps=False install \
        alsa-plugins-pulseaudio alsa-utils pulseaudio-utils \
        ty ruff clang-tools-extra rust-analyzer rust-src tree-sitter-cli \
    && dnf clean all \
    && rpm -qa | sort > /usr/local/share/sandbox-rpms.txt

COPY --from=tools /opt/sandbox/ /opt/sandbox/
COPY --from=tools /usr/local/bin/ /usr/local/bin/
COPY --from=editors /opt/sandbox/ /opt/sandbox/
COPY --from=editors /usr/local/bin/ /usr/local/bin/
COPY --from=agents /opt/sandbox/ /opt/sandbox/
COPY --from=agents /usr/local/bin/ /usr/local/bin/
COPY --from=agents /usr/local/share/sandbox-agents.txt /usr/local/share/sandbox-agents.txt
COPY --from=tools /usr/local/share/sandbox-tools.txt /usr/local/share/sandbox-tools.txt
RUN cat /usr/local/share/sandbox-agents.txt >> /usr/local/share/sandbox-tools.txt

COPY container/lazyvim/ /opt/sandbox/lazyvim/
COPY container/nvim /usr/local/bin/nvim
COPY container/helix-config.toml /opt/sandbox/helix/config.toml
COPY container/helix-languages.toml /opt/sandbox/helix/languages.toml
COPY container/hx /usr/local/bin/hx
RUN chmod 0755 /usr/local/bin/nvim /usr/local/bin/hx

COPY container/browser-skill.md /opt/sandbox/skills/agent-browser/SKILL.md
RUN for skills_dir in /home/agent/.agents/skills /home/agent/.claude/skills; do \
        install -d -o agent -g agent "${skills_dir%/skills}" "$skills_dir" "$skills_dir/agent-browser" \
        && install -m 0644 -o agent -g agent /opt/sandbox/skills/agent-browser/SKILL.md \
            "$skills_dir/agent-browser/SKILL.md" \
        || exit 1; \
    done

ENV HOME=/home/agent \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/home/agent/.local/bin:/home/agent/.cargo/bin:/home/agent/.bun/bin \
    AGENT_BROWSER_EXECUTABLE_PATH=/usr/local/bin/sandbox-chromium \
    DISABLE_AUTOUPDATER=1
WORKDIR /workspace
USER agent:agent
RUN codex --version && claude --version && grok --version && agent-browser --version \
    && bun --version && uv --version && python3 --version && hc --version \
    && /usr/bin/nvim --version \
    && test -x /usr/local/bin/roslyn-language-server \
    && hx --health c-sharp | rg 'roslyn-language-server' \
    && test -x "$AGENT_BROWSER_EXECUTABLE_PATH"
CMD ["codex"]
