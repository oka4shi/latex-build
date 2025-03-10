FROM ubuntu:noble AS base
ARG TARGETARCH

FROM base AS build-arm64
ARG AWS_CLI_ARCH=linux-aarch64
ARG TEX_LIVE_ARCH=aarch64-linux

FROM base AS build-amd64
ARG AWS_CLI_ARCH=linux-x86_64
ARG TEX_LIVE_ARCH=x86_64-linux

FROM build-${TARGETARCH}

# WORD内部向けコンテナなので、何か問題が有ったらSlack上で通知して下さい。
LABEL maintainer="Totsugekitai <37617413+Totsugekitai@users.noreply.github.com>"

ARG PERSISTENT_DEPS="ca-certificates tzdata tar fontconfig unzip wget curl \
      make perl ghostscript bash git groff less fonts-ebgaramond"

# キャッシュ修正とパッケージインストールは同時にやる必要がある
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    $PERSISTENT_DEPS

# install awscliv2
RUN curl "https://awscli.amazonaws.com/awscli-exe-$AWS_CLI_ARCH.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -r ./aws awscliv2.zip

ARG FONT_URLS="https://github.com/adobe-fonts/source-code-pro/archive/2.030R-ro/1.050R-it.zip \
      https://github.com/adobe-fonts/source-han-sans/releases/latest/download/SourceHanSansJP.zip \
      https://github.com/adobe-fonts/source-han-serif/raw/release/SubsetOTF/SourceHanSerifJP.zip"
ARG FONT_PATH="/usr/share/fonts/"
RUN mkdir -p $FONT_PATH && \
    wget $FONT_URLS && \
    unzip -j "*.zip" "*.otf" -d $FONT_PATH && \
    rm *.zip && \
    fc-cache -f -v

RUN cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    echo 'Asia/Tokyo' > /etc/timezone

# Install TeXLive
# ENV TEXLIVE_PATH /usr/local/texlive
# RUN mkdir -p /tmp/install-tl-unx && \
#     wget -qO- http://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz | \
#       tar -xz -C /tmp/install-tl-unx --strip-components=1 && \
#     printf "%s\n" \
#       "TEXDIR $TEXLIVE_PATH" \
#       "selected_scheme scheme-small" \
#       "option_doc 0" \
#       "option_src 0" \
#       "option_autobackup 0" \
#       > /tmp/install-tl-unx/texlive.profile && \
#     /tmp/install-tl-unx/install-tl \
#       -profile /tmp/install-tl-unx/texlive.profile

# ENV PATH $TEXLIVE_PATH/bin/x86_64-linux:$TEXLIVE_PATH/bin/aarch64-linux:$PATH

COPY --from=registry.gitlab.com/islandoftex/images/texlive:latest-small /usr/local/texlive /usr/local/texlive

RUN echo "Set PATH to $PATH" && \
    $(find /usr/local/texlive -name tlmgr) path add

# tlmgr section
RUN tlmgr update --self

ARG DEPS_FOR_TLMGR="latexmk collection-luatex collection-langjapanese \
      collection-fontsrecommended type1cm mdframed needspace newtx \
      fontaxes boondox everyhook svn-prov framed subfiles titlesec tocdata \
      biblatex pbibtex-base logreq biber import environ trimspaces tcolorbox \
      ebgaramond algorithms algorithmicx xstring siunitx bussproofs enumitem"

# /tlmgr-pkgsにtlmgrのパッケージをバックアップして次回以降のビルド時に再利用する
# package install
RUN --mount=type=cache,target=/tlmgr-pkgs,sharing=locked \
    tlmgr list --only-installed | grep '^i ' | awk '{print $2}' | sed 's/:$//' > /tmp/installed-packages.txt && \
    tlmgr restore --force --backupdir /tlmgr-pkgs --all || true && \
    tlmgr install --no-persistent-downloads ${DEPS_FOR_TLMGR} && \
    tlmgr backup --clean --backupdir /tlmgr-pkgs --all && \
    tlmgr list --only-installed | grep '^i ' | awk '{print $2}' | sed 's/:$//' > /tmp/current_installed_packages.txt && \
    bash -c 'comm -23 <(sort /tmp/current_installed_packages.txt) <(sort /tmp/installed-packages.txt) > /tmp/new_packages.txt' && \
    tlmgr backup $(cat /tmp/new_packages.txt) --backupdir /tlmgr-pkgs && \
    tlmgr path add

# EBGaramond
RUN cp /usr/share/fonts/opentype/ebgaramond/EBGaramond12-Regular.otf "/usr/share/fonts/opentype/EB Garamond.otf" && \
    fc-cache -frvv && \
    luaotfload-tool --update

# Install Pandoc
ARG PANDOC_VERSION="3.5"
ARG PANDOC_DOWNLOAD_URL="https://github.com/jgm/pandoc/releases/download/$PANDOC_VERSION/pandoc-$PANDOC_VERSION-linux-$TARGETARCH.tar.gz"
ARG PANDOC_ROOT="/usr/local/bin/pandoc"
RUN wget -qO- "$PANDOC_DOWNLOAD_URL" | tar -xzf - && \
    cp pandoc-$PANDOC_VERSION/bin/pandoc $PANDOC_ROOT && \
    rm -Rf pandoc-$PANDOC_VERSION/

VOLUME ["/workdir"]

WORKDIR /workdir

CMD ["/bin/bash", "-c", "fc-cache && make"]
