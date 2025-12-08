#!/bin/bash

source config.sh

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | deps | write_config | download | setup_clang | configure | build | install | compress | deb | release ) action=$1 ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_deps() {
    if [[ $(command -v apt) ]]; then
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
        else
            echo "Error: /etc/os-release not found. Cannot determine distribution."
            exit 1
        fi
        case "$ID" in
            debian)
                apt update && apt upgrade -y
                apt install -y curl wget build-essential libreadline-dev libncursesw5-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev zlib1g-dev python3 python3-dev git patchelf file libgdbm-dev liblzma-dev 
                ;;
            *)
                echo "Unsupported distribution: $ID"
                exit 1
                ;;
        esac
    else
        echo "Your selected distribution is not supported."
        exit 1
    fi
}

function do_write_config() {
    cd "$BASE_DIR" || exit 1
    echo "#!/bin/bash" > config.sh
    echo "export BASE_DIR=$BASE_DIR" >> config.sh
    echo 'export PATH="$BASE_DIR/clang/bin:$PATH"' >> config.sh
    python_version=$(echo "$TARBALL_URL" | grep -oP 'Python-\K[0-9]+\.[0-9]+')
    python_version_full=$(echo "$TARBALL_URL" | grep -oP 'Python-\K[0-9]+\.[0-9]+\.[0-9]+')
    echo "export PYTHON_VERSION=$python_version" >> config.sh
    echo "export PYTHON_VERSION_FULL=$python_version_full" >> config.sh
    echo "export TARBALL_URL=$TARBALL_URL" >> config.sh
    if [[ -n $INSTALL_PATH ]]; then
        echo "export INSTALL_PATH=$INSTALL_PATH" >> config.sh
    else
        echo "export INSTALL_PATH=/opt/python$python_version" >> config.sh
    fi
    if [[ -n $ENABLE_JIT ]];then
        echo "export ENABLE_JIT=$ENABLE_JIT" >> config.sh
    else
        echo "export ENABLE_JIT=0" >> config.sh
    fi
    if [[ $(command -v apt) ]]; then
        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
        else
            echo "Error: /etc/os-release not found. Cannot determine distribution."
            exit 1
        fi
        echo "export DISTRO=debian" >> config.sh
        echo "export DISTRO_VERSION=$VERSION_ID" >> config.sh
    else
        echo "Your selected distribution is not supported."
        exit 1
    fi
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            echo "export ARCH=x86_64" >> config.sh
            ;;
        aarch64)
            echo "export ARCH=aarch64" >> config.sh
            ;;
        *)
            echo "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
}

function do_download() {
    cd "$BASE_DIR" || exit 1
    if [[ "$TARBALL_URL" == *.tar.gz || "$TARBALL_URL" == *.tgz ]];then
        curl -L "$TARBALL_URL" | tar -xz
    elif [[ "$TARBALL_URL" == *.tar.xz ]];then
        curl -L "$TARBALL_URL" | tar -xJ
    else
        echo "Unsupported archive format. Only .tgz, .tar.gz and .tar.xz are supported."
        exit 1
    fi
}

function do_setup_clang() {
    if [[ $ARCH = "x86_64" ]]; then
        if [[ $DISTRO = "debian" ]]; then
            clang_url="https://github.com/Mayuri-Chan/clang/releases/download/21.0.0git-e64f8e043/Mayuri-clang_21.0.0git-bookworm-adfea33f0.tar.xz"
        else
            echo "Unsupported distribution for x86_64 architecture."
            exit 1
        fi
    else
        if [[ $DISTRO = "debian" ]]; then
            clang_url="https://github.com/Mayuri-Chan/clang/releases/download/21.0.0git-e64f8e043/Mayuri-clang_21.0.0git-bookworm-aarch64-adfea33f0.tar.xz"
        else
            echo "Unsupported distribution for ARM64 architecture."
            exit 1
        fi
    fi
    mkdir -p "$BASE_DIR"/clang
    cd "$BASE_DIR"/clang || exit 1
    wget -q --show-progress "$clang_url"
    if [[ $clang_url == *.tar.gz ]]; then
        tar -xzf *.tar.gz
    elif [[ $clang_url == *.tar.xz ]]; then
        tar -xJf *.tar.xz
    else
        echo "Unsupported archive format."
        exit 1
    fi
    clang_name=$(basename "$clang_url")
    if [[ "$clang_name" == "LLVM-"* ]]; then
        mv "$BASE_DIR"/clang/LLVM-*/* "$BASE_DIR"/clang/
        rm -rf "$BASE_DIR"/clang/LLVM-*
    fi
}

function do_configure() {
    if [[ "$ARCH" == "x86_64" ]]; then
        TARGET=x86_64-pc-linux-gnu
        HOST=x86_64-pc-linux-gnu
        BUILD=x86_64-pc-linux-gnu
    else
        TARGET=aarch64-unknown-linux-gnu
        HOST=aarch64-unknown-linux-gnu
        BUILD=aarch64-unknown-linux-gnu
    fi
    cd "$BASE_DIR"/Python-* || exit 1
    EXTRAFLAGS=""
    if [[ "$ENABLE_JIT" == "1" ]]; then
        EXTRAFLAGS+=" --enable-experimental-jit"
    fi
    sed -i 's#gitid = "main";#gitid = "'"$VENDOR_STRING"'";#g' Modules/getbuildinfo.c
    ./configure --prefix="$INSTALL_PATH" --target=$TARGET \
      --enable-shared --build=$BUILD --host=$HOST \
      --with-computed-gotos \
      --enable-optimizations \
      --with-lto \
      --enable-ipv6 \
      --with-dbmliborder=gdbm:ndbm \
      --enable-loadable-sqlite-extensions \
      --with-tzpath=/usr/share/zoneinfo \
      CC=$(which clang) \
      CXX=$(which clang++) \
      LLVM_AR=$(which llvm-ar) \
      LLVM_RANLIB=$(which llvm-ranlib) \
      LLVM_OBJCOPY=$(which llvm-objcopy) \
      LLVM_OBJDUMP=$(which llvm-objdump) \
      LLVM_NM=$(which llvm-nm) \
      LLVM_STRIP=$(which llvm-strip) \
      LLVM_PROFDATA=$(which llvm-profdata) \
      LDFLAGS="-Wl,--rpath=$INSTALL_PATH/lib -fuse-ld=lld" \
      $EXTRAFLAGS || exit 1
}

function do_build(){
    cd "$BASE_DIR"/Python-* || exit 1
    make -j$(nproc)
}

function do_install() {
    cd "$BASE_DIR"/Python-* || exit 1
    make altinstall

    # Strip remaining binaries
    for f in $(find "$INSTALL_PATH" -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
        strip -s "${f::-1}"
    done
}

function do_compress() {
    cd "$BASE_DIR"/Python-* || exit 1
    mkdir -p "$BASE_DIR"/dist
    tar -cJf "$BASE_DIR"/dist/python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz -C "$INSTALL_PATH" .
}

function do_deb() {
    sed -i "s/<version>/$PYTHON_VERSION/g" "$BASE_DIR"/package_root/DEBIAN/control
    sed -i "s/<full_version>/$PYTHON_VERSION_FULL/g" "$BASE_DIR"/package_root/DEBIAN/control
    if [[ "$ARCH" == "aarch64" ]]; then
        sed -i "s/<arch>/arm64/g" "$BASE_DIR"/package_root/DEBIAN/control
    else
        sed -i "s/<arch>/amd64/g" "$BASE_DIR"/package_root/DEBIAN/control
    fi
    mkdir -p "$BASE_DIR"/package_root"$INSTALL_PATH"
    cp -r "$INSTALL_PATH"/* "$BASE_DIR"/package_root"$INSTALL_PATH"/
    dpkg-deb --build "$BASE_DIR"/package_root "$BASE_DIR"/dist/python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.deb
}

function do_release() {
    export GITHUB_TOKEN
    export GITHUB_REPOSITORY
    cd "$BASE_DIR"/dist || exit 1
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "GITHUB_TOKEN is not set. Skipping release."
        exit 0
    fi
    tag="python-v$PYTHON_VERSION_FULL"
    release_name="Python $PYTHON_VERSION_FULL"
    release_body="Python $PYTHON_VERSION_FULL\nInstall path: $INSTALL_PATH"
    asset="python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.tar.xz"
    git config --global --add safe.directory "$BASE_DIR"

    # Check if tag exists
    if curl -sf -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/git/refs/tags/$tag" >/dev/null; then
        echo "Tag $tag already exists. Skipping tag creation."
    else
        # Create tag
        git tag "$tag"
        git push origin "$tag"
        echo "Tag $tag created and pushed."
    fi

    # Create release (idempotent)
    release_id=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/tags/$tag" | grep '"id":' | head -1 | grep -o '[0-9]\+')
    if [[ -z "$release_id" ]]; then
        # Create release if not exists
        response=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
            -d "{\"tag_name\":\"$tag\",\"name\":\"$release_name\",\"body\":\"$release_body\",\"draft\":false,\"prerelease\":false}" \
            "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases")
        release_id=$(echo "$response" | grep '"id":' | head -1 | grep -o '[0-9]\+')
    fi

    # Upload asset
    if [[ -n "$release_id" ]]; then
        curl -s -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/gzip" \
            --data-binary @"$asset" \
            "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$release_id/assets?name=$(basename "$asset")"
        curl -s -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/vnd.debian.binary-package" \
            --data-binary @"python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.deb" \
            "https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/$release_id/assets?name=python-$PYTHON_VERSION_FULL-$DISTRO-$DISTRO_VERSION-$ARCH.deb"
        echo "Asset uploaded to release."
    else
        echo "Failed to create or find release."
        exit 1
    fi
}

function do_all() {
    do_deps
    do_write_config
    do_setup_clang
    do_download
    do_configure
    do_build
    do_install
    do_compress
    do_deb
}

parse_parameters "$@"
do_"${action:=all}"
