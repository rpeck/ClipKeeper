# Sourced by the build scripts. Sets SWIFT_BUILD_FLAGS for `swift build` and `swift test`.
#
# Some Command Line Tools installs ship an empty C++ header folder in the
# toolchain (only __cxx_version), and the C++ standard library headers live
# only in the SDK. BoringSSL, inside swift-nio-ssl, is C++, so point its
# compiles at the SDK headers in that case. A complete toolchain gets no flag.
SWIFT_BUILD_FLAGS=()
_ck_toolchain_cxx="${DEVELOPER_DIR}/usr/include/c++/v1"
_ck_sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ ! -f "$_ck_toolchain_cxx/memory" && -n "$_ck_sdk" && -f "$_ck_sdk/usr/include/c++/v1/memory" ]]; then
  SWIFT_BUILD_FLAGS=(-Xcxx -isystem -Xcxx "$_ck_sdk/usr/include/c++/v1")
fi
unset _ck_toolchain_cxx _ck_sdk
