#!/bin/bash

# 出错退出
set -e

# 颜色
RED='\033[0;31m'
NC='\033[0m'

# 编译路径变量
BASE="/build"
PREFIX="$BASE/stage"
SRC="$BASE/src"
DIST="$BASE/dist"

# libev
LIBEV_VER=4.24
LIBEV_NAME=libev-${LIBEV_VER}
LIBEV_URL=http://dist.schmorp.de/libev/${LIBEV_NAME}.tar.gz

## mbedTLS
MBEDTLS_VER=2.9.0
MBEDTLS_NAME=mbedtls-${MBEDTLS_VER}
MBEDTLS_URL=https://tls.mbed.org/download/${MBEDTLS_NAME}-apache.tgz

## Sodium
SODIUM_VER=1.0.16
SODIUM_NAME=libsodium-${SODIUM_VER}
SODIUM_URL=https://download.libsodium.org/libsodium/releases/${SODIUM_NAME}.tar.gz

## PCRE
PCRE_VER=8.42
PCRE_NAME=pcre-${PCRE_VER}
PCRE_URL=https://ftp.pcre.org/pub/pcre/${PCRE_NAME}.tar.gz

## c-ares
CARES_VER=1.14.0
CARES_NAME=c-ares-${CARES_VER}
CARES_URL=https://c-ares.haxx.se/download/${CARES_NAME}.tar.gz

#shadowsocks-libev
SHADOWSOCKS_VER=3.2.0
SHADOWSOCKS_NAME=shadowsocks-libev-${SHADOWSOCKS_VER}
SHADOWSOCKS_URL=https://github.com/shadowsocks/shadowsocks-libev/releases/download/v${SHADOWSOCKS_VER}/${SHADOWSOCKS_NAME}.tar.gz

# 工具
# upx
mkdir -p "${SRC}"

UPX_VER=3.94
UPX_NAME=upx-${UPX_VER}-amd64_linux
UPX_URL=https://github.com/upx/upx/releases/download/v${UPX_VER}/${UPX_NAME}.tar.xz
cd ${SRC}
wget ${UPX_URL}
tar -Jxf "${UPX_NAME}.tar.xz"
mv ${UPX_NAME}/upx /usr/bin

apt-get update -y
apt-get install --no-install-recommends -y build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu automake autoconf libtool aria2


# 下载源码
cd "${SRC}"
DOWN="aria2c --file-allocation=trunc -s10 -x10 -j10 -c"
for pkg in LIBEV SODIUM MBEDTLS PCRE CARES SHADOWSOCKS
do
    name=${pkg}_NAME
    url=${pkg}_URL
    filename="${!name}".tar.gz
    $DOWN ${!url} -o "${filename}"
    echo "正在解压 ${filename}..."
    tar xf ${filename}
done

# 编译
build_deps() {
    # 静态编译参数
    arch=$1
    host=$arch-linux-gnu
    prefix=${PREFIX}/$arch
    args="--host=${host} --prefix=${prefix} --disable-shared --enable-static"

    # libev
    cd "$SRC/$LIBEV_NAME"
    ./configure $args
    make clean
    make install

    # mbedtls
    cd "$SRC/$MBEDTLS_NAME"
    make clean
    make DESTDIR="${prefix}" CC="${host}-gcc" AR="${host}-ar" LD="${host}-ld" LDFLAGS=-static install
    unset DESTDIR

    # sodium
    cd "$SRC/$SODIUM_NAME"
    ./configure $args
    make clean
    make install

    # pcre
    cd "$SRC/$PCRE_NAME"
    ./configure $args \
      --enable-unicode-properties --enable-utf8
    make clean
    make install

    # c-ares
    cd "$SRC/$CARES_NAME"
    ./configure $args
    make clean
    make install
}

dk_deps() {
    for arch in x86_64 aarch64
    do
        build_deps $arch
    done
}

dk_deps


build_proj() {
    arch=$1
    host=$arch-linux-gnu
    prefix=${DIST}/$arch
    dep=${PREFIX}/$arch 

    cd "$SRC/$SHADOWSOCKS_NAME"
    ./configure LIBS="-lpthread -lm" \
        LDFLAGS="-Wl,-static -static -static-libgcc -L$dep/lib" \
        CFLAGS="-I$dep/include" \
        --host=${host} \
        --prefix=${prefix} \
        --disable-ssp \
        --disable-documentation \
        --with-mbedtls="$dep" \
        --with-pcre="$dep" \
        --with-sodium="$dep" \
        --with-cares="$dep"
    make clean
    make install-strip
}

dk_build() {
    for arch in x86_64 aarch64
    do
        build_proj $arch
    done
}

dk_build


rm -rf "$BASE/pack"
mkdir -p "$BASE/pack"
cd "$BASE/pack"
mkdir -p shadowsocks-libev
cd shadowsocks-libev
mkdir -p aarch64
mkdir -p x86_64

for bin in local server tunnel
do
    cp ${DIST}/aarch64/bin/ss-${bin} aarch64
    cp ${DIST}/x86_64/bin/ss-${bin} x86_64
    upx aarch64/ss-${bin}
    upx x86_64/ss-${bin}
done

cd "$BASE/pack"
tar -Jcf bin.tar.xz shadowsocks-libev
echo -e "${RED}${BASE}/pack/bin.tar.gz 打包完毕${NC}"