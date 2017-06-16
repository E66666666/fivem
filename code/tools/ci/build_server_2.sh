#!/bin/sh

# fail on error
set -e

# add testing repository
echo http://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
echo http://runtime.fivem.net/build/testing >> /etc/apk/repositories

cat <<EOT > /etc/apk/keys/peachypies@protonmail.ch-592da20a.rsa.pub
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtDPY0/CXURivt0aGMovm
+DPLN24riKcjOfjeAsK69ZINgrpx4A5ictIUJsYSjj3I4+GvowIcR9O0GTuOvPdl
+6u847G0gHYD2bJb+vTTNEL/fFIgF8BzE0GIa+yEf91AlvP6XlFHYP0BkeJmdYyN
1UYsXj9t7snmdlztOrjlRTtL0eHbQJ0W4YWvdR4hkESVUlXBbKfWgMKLsTZjlgRj
hSaDKqAr4nDdOw+zs34fp3Q0MaF/+BOjXnKhtopYR3SleCtyHZStXuQ05aDRAnPD
EZbiYDZCAgX0GU3dsnPDcZYKOyra3BH4ISIao4X+L0vh2N7am4y+TOm7VjCKJAOn
wwIDAQAB
-----END PUBLIC KEY-----
EOT

# update apk cache
apk --no-cache update
apk --no-cache upgrade

# install runtime dependencies
apk add libc++ curl libssl1.0 libunwind libstdc++

# install compile-time dependencies
apk add --no-cache --virtual .dev-deps libc++-dev curl-dev clang clang-dev build-base linux-headers openssl-dev python2 py2-pip lua5.3 lua5.3-dev mono-dev

# install ply
pip install ply

# download and build premake
curl -sLo /tmp/premake.zip https://github.com/premake/premake-core/releases/download/v5.0.0-alpha11/premake-5.0.0-alpha11-src.zip

cd /tmp
unzip -q premake.zip
rm premake.zip
cd premake-*

cd build/gmake.unix/
make -j4
cd ../../

mv bin/release/premake5 /usr/local/bin
cd ..

rm -rf premake-*

# download and extract boost
curl -sLo /tmp/boost.tar.bz2 https://dl.bintray.com/boostorg/release/1.64.0/source/boost_1_64_0.tar.bz2
tar xf boost.tar.bz2
rm boost.tar.bz2

mv boost_* boost

export BOOST_ROOT=/tmp/boost/

# build CitizenFX
cd /src/code

cp -a ../vendor/curl/include/curl/curlbuild.h.dist ../vendor/curl/include/curl/curlbuild.h

premake5 gmake --game=server --cc=clang --dotnet=msnet
cd build/server/linux

export CXXFLAGS="-std=c++1z -stdlib=libc++"

make clean
make clean config=release
make -j4 config=release

cd ../../../

# build an output tree
mkdir -p /opt/cfx-server

cp -a ../data/shared/* /opt/cfx-server
cp -a ../data/server/* /opt/cfx-server
cp -a bin/server/linux/release/FXServer /opt/cfx-server
cp -a bin/server/linux/release/*.so /opt/cfx-server
cp -a bin/server/linux/release/*.json /opt/cfx-server
cp tools/ci/run.sh /opt/cfx-server
chmod +x /opt/cfx-server/run.sh

mkdir -p /opt/cfx-server/citizen/clr2/cfg/4.5/
mkdir -p /opt/cfx-server/citizen/clr2/lib/mono/4.5/

cp -a bin/server/linux/release/citizen/ /opt/cfx-server
cp -a ../data/client/citizen/clr2/lib/mono/4.5/MsgPack.dll /opt/cfx-server/citizen/clr2/lib/mono/4.5/

cp -a /usr/lib/mono/4.5/Facades/ /opt/cfx-server/citizen/clr2/lib/mono/4.5/Facades/

for dll in Microsoft.CSharp.dll Mono.CSharp.dll Mono.Posix.dll mscorlib.dll \
	System.Configuration.dll System.Core.dll System.Data.dll System.dll System.EnterpriseServices.dll \
	System.Net.dll System.Net.Http.dll System.Numerics.Vectors.dll System.Runtime.InteropServices.RuntimeInformation.dll System.Runtime.Serialization.dll \
	System.ServiceModel.Internals.dll System.Transactions.dll System.Xml.dll System.Xml.Linq.dll; do
	cp /usr/lib/mono/4.5/$dll /opt/cfx-server/citizen/clr2/lib/mono/4.5/
done

# strip output files
strip --strip-unneeded /opt/cfx-server/*.so
strip --strip-unneeded /opt/cfx-server/FXServer

cd /src/ext/natives
gcc -O2 -shared -fpic -o cfx.so -I/usr/include/lua5.3/ lua_cfx.c

lua5.3 codegen.lua > /opt/cfx-server/citizen/scripting/lua/natives_server.lua

cd /opt/cfx-server

# clean up
rm -rf /tmp/boost

apk del .dev-deps
