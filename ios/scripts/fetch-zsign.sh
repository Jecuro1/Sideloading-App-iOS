#!/usr/bin/env bash
# Downloads the zsign sources (MIT) into the ZSignKit package and adapts them for iOS.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${ZSIGN_VERSION:-v1.1.3}"
DEST="Packages/ZSignKit/Sources/CZSign/zsign"

if [ -f "$DEST/.version" ] && [ "$(cat "$DEST/.version")" = "$VERSION" ]; then
  echo "zsign $VERSION ist bereits vorhanden."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 --branch "$VERSION" https://github.com/zhlynn/zsign "$TMP/zsign"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$TMP/zsign/src" "$DEST/src"
cp "$TMP/zsign/LICENSE" "$DEST/LICENSE"

# Not needed / not available on iOS
rm -f "$DEST"/src/third-party/minizip/iowin32.* "$DEST"/src/third-party/minizip/mztools.*

# OpenSSL ships as OpenSSL.framework: use its header spelling
grep -rl '<openssl/' "$DEST/src" | xargs perl -pi -e 's#<openssl/#<OpenSSL/#g'

# Export the command line entry point as a C function instead of main()
perl -pi -e 's/^int main\(int argc, char\* argv\[\]\)/extern "C" int zsign_main(int argc, char* argv[])/' "$DEST/src/zsign.cpp"
grep -q 'extern "C" int zsign_main' "$DEST/src/zsign.cpp"

# iOS apps cannot spawn processes (only used for -i and requirement printing)
perl -pi -e 's/pid_t pid = fork\(\);/pid_t pid = -1;/; s/^\s*execlp\(.*$/\t\t;/' "$DEST/src/zsign.cpp"
perl -pi -e 's/FILE\* cmd = popen\(strCommand\.c_str\(\), "r"\);/FILE* cmd = NULL;/; s/pclose\(cmd\);/(void)cmd;/' "$DEST/src/signing.cpp"

echo "$VERSION" > "$DEST/.version"
echo "zsign $VERSION nach $DEST geladen."
