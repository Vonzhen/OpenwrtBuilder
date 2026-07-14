#!/bin/sh

set -eu

die() {
	printf '%s\n' "error: $*" >&2
	exit 1
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
CONFIG_FILE="$SCRIPT_DIR/build.env"

[ -f "$CONFIG_FILE" ] || die "missing configuration: $CONFIG_FILE"
# shellcheck source=build.env
. "$CONFIG_FILE"

: "${OPENWRT_DOWNLOAD_BASE:?missing OPENWRT_DOWNLOAD_BASE}"
: "${OPENWRT_RELEASE_SERIES:?missing OPENWRT_RELEASE_SERIES}"
: "${OPENWRT_TARGET:?missing OPENWRT_TARGET}"
: "${OPENWRT_SUBTARGET:?missing OPENWRT_SUBTARGET}"
: "${OPENWRT_PROFILE:?missing OPENWRT_PROFILE}"
: "${ROOTFS_FILESYSTEM:?missing ROOTFS_FILESYSTEM}"
: "${IMAGE_FLAVOR:?missing IMAGE_FLAVOR}"
: "${ROOTFS_PARTSIZE:?missing ROOTFS_PARTSIZE}"
: "${ARTIFACT_BASENAME:?missing ARTIFACT_BASENAME}"
: "${CUSTOM_PACKAGES:?missing CUSTOM_PACKAGES}"
: "${CUSTOM_APK_REPOSITORY_URL:?missing CUSTOM_APK_REPOSITORY_URL}"
: "${CUSTOM_APK_PUBLIC_KEY_SHA256:?missing CUSTOM_APK_PUBLIC_KEY_SHA256}"

printf '%s\n' "$OPENWRT_RELEASE_SERIES" | grep -Eq '^[0-9]+\.[0-9]+$' ||
	die "invalid release series: $OPENWRT_RELEASE_SERIES"

case "$ROOTFS_PARTSIZE" in
	*[!0-9]*|'') die "ROOTFS_PARTSIZE must be a positive integer" ;;
	0) die "ROOTFS_PARTSIZE must be greater than zero" ;;
esac

for package_name in $CUSTOM_PACKAGES; do
	printf '%s\n' "$package_name" | grep -Eq '^[a-z0-9][a-z0-9+_.-]*$' ||
		die "invalid custom package name: $package_name"
done

fetch() {
	url=$1
	destination=$2
	curl --fail --silent --show-error --location --retry 3 \
		--output "$destination" "$url"
}

resolve_version() {
	index_file=${OPENWRT_RELEASES_INDEX_FILE:-}
	remove_index=false

	if [ -z "$index_file" ]; then
		need_command curl
		index_file=$(mktemp)
		remove_index=true
		fetch "$OPENWRT_DOWNLOAD_BASE/" "$index_file"
	fi

	[ -f "$index_file" ] || die "release index not found: $index_file"
	escaped_series=$(printf '%s\n' "$OPENWRT_RELEASE_SERIES" | sed 's/\./\\./g')
	version=$(
		grep -Eo "$escaped_series\.[0-9]+/" "$index_file" |
			sed 's#/$##' |
			sort -Vu |
			tail -n 1
	)

	if [ "$remove_index" = true ]; then
		rm -f -- "$index_file"
	fi

	[ -n "$version" ] || die "no stable ${OPENWRT_RELEASE_SERIES}.x release found"
	printf '%s\n' "$version"
}

verify_customizations() {
	public_key="$REPO_ROOT/files/etc/apk/keys/openwrt-packages-addon.pem"
	custom_feed="$REPO_ROOT/files/etc/apk/repositories.d/customfeeds.list"
	lan_defaults="$REPO_ROOT/files/etc/uci-defaults/99-custom-lan-ip"
	upgrade_keep="$REPO_ROOT/files/lib/upgrade/keep.d/openwrt-builder"

	[ -f "$public_key" ] || die "missing custom APK public key"
	actual_key_hash=$(sha256sum "$public_key" | awk '{print $1}')
	[ "$actual_key_hash" = "$CUSTOM_APK_PUBLIC_KEY_SHA256" ] ||
		die "custom APK public key SHA-256 mismatch"
	openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1 ||
		die "custom APK public key is not a valid PEM public key"

	[ -f "$custom_feed" ] || die "missing custom APK repository configuration"
	[ "$(grep -Fxc "$CUSTOM_APK_REPOSITORY_URL" "$custom_feed")" -eq 1 ] ||
		die "custom APK repository configuration is missing or unexpected"
	[ "$(sed '/^[[:space:]]*$/d' "$custom_feed" | wc -l)" -eq 1 ] ||
		die "custom APK repository file must contain exactly one entry"

	[ -x "$lan_defaults" ] || die "LAN default configuration script is not executable"
	[ "$(grep -Fxc "uci -q set network.lan.ipaddr='10.10.11.1'" "$lan_defaults")" -eq 1 ] ||
		die "default LAN address is missing or unexpected"
	[ -f "$upgrade_keep" ] || die "missing project sysupgrade keep rules"
	[ "$(sed '/^[[:space:]]*$/d' "$upgrade_keep" | wc -l)" -eq 3 ] ||
		die "project sysupgrade keep file must contain exactly three entries"
	for keep_path in \
		'/etc/shinra/' \
		'/etc/apk/keys/openwrt-packages-addon.pem' \
		'/etc/apk/repositories.d/customfeeds.list'; do
		grep -Fxq "$keep_path" "$upgrade_keep" ||
			die "missing project sysupgrade keep path: $keep_path"
	done
	[ ! -e "$REPO_ROOT/files/etc/sysupgrade.conf" ] ||
		die "project must not replace the official /etc/sysupgrade.conf"
	[ ! -e "$REPO_ROOT/files/usr/libexec/package-manager-call" ] ||
		die "project must not override the official LuCI package manager"

	if grep -R -n -- '--allow-untrusted' "$REPO_ROOT/files" >/dev/null 2>&1; then
		die "unsigned APK installation override is forbidden"
	fi
}

OPENWRT_VERSION=$(resolve_version)

if [ "${1:-}" = "--resolve-version" ]; then
	printf '%s\n' "$OPENWRT_VERSION"
	exit 0
fi

[ "$#" -eq 0 ] || die "usage: $0 [--resolve-version]"

for command_name in curl sha256sum awk sed grep sort tail tar make find diff comm mktemp openssl tr wc cat od; do
	need_command "$command_name"
done

verify_customizations

TARGET_URL="$OPENWRT_DOWNLOAD_BASE/$OPENWRT_VERSION/targets/$OPENWRT_TARGET/$OPENWRT_SUBTARGET"
IMAGEBUILDER_ARCHIVE="openwrt-imagebuilder-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET.Linux-x86_64.tar.zst"
EXPECTED_IMAGE="openwrt-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET-$OPENWRT_PROFILE-$ROOTFS_FILESYSTEM-$IMAGE_FLAVOR.img.gz"
OFFICIAL_MANIFEST_NAME="openwrt-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET.manifest"

CACHE_ROOT="$REPO_ROOT/.cache"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$CACHE_ROOT" "$DIST_DIR"
WORK_DIR=$(mktemp -d "$CACHE_ROOT/imagebuilder.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT HUP INT TERM

SHA256SUMS="$WORK_DIR/sha256sums"
ARCHIVE_PATH="$WORK_DIR/$IMAGEBUILDER_ARCHIVE"
OFFICIAL_MANIFEST="$WORK_DIR/$OFFICIAL_MANIFEST_NAME"
OFFICIAL_PACKAGE_NAMES="$WORK_DIR/official-package-names"
PLANNED_MANIFEST="$WORK_DIR/planned.manifest"
PLANNED_PACKAGE_NAMES="$WORK_DIR/planned-package-names"
BUILT_PACKAGE_NAMES="$WORK_DIR/built-package-names"
MISSING_OFFICIAL_PACKAGES="$WORK_DIR/missing-official-packages"
PACKAGE_DIFF="$WORK_DIR/package.diff"
CUSTOM_APK_INDEX="$WORK_DIR/custom-packages.adb"

fetch "$TARGET_URL/sha256sums" "$SHA256SUMS"
fetch "$TARGET_URL/$IMAGEBUILDER_ARCHIVE" "$ARCHIVE_PATH"
fetch "$TARGET_URL/$OFFICIAL_MANIFEST_NAME" "$OFFICIAL_MANIFEST"
fetch "$CUSTOM_APK_REPOSITORY_URL" "$CUSTOM_APK_INDEX"

custom_index_magic=$(od -An -tx1 -N4 "$CUSTOM_APK_INDEX" | tr -d ' \n')
[ "$custom_index_magic" = "41444264" ] || die "custom APK repository index has an unexpected format"

expected_hash=$(awk -v name="$IMAGEBUILDER_ARCHIVE" '$2 == name || $2 == "*" name { print $1 }' "$SHA256SUMS")
[ "$(printf '%s\n' "$expected_hash" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "ImageBuilder has zero or multiple checksum entries"
actual_hash=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
[ "$actual_hash" = "$expected_hash" ] || die "ImageBuilder SHA-256 verification failed"

expected_manifest_hash=$(awk -v name="$OFFICIAL_MANIFEST_NAME" '$2 == name || $2 == "*" name { print $1 }' "$SHA256SUMS")
[ "$(printf '%s\n' "$expected_manifest_hash" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "official manifest has zero or multiple checksum entries"
actual_manifest_hash=$(sha256sum "$OFFICIAL_MANIFEST" | awk '{print $1}')
[ "$actual_manifest_hash" = "$expected_manifest_hash" ] ||
	die "official manifest SHA-256 verification failed"

awk '$2 == "-" { print $1 }' "$OFFICIAL_MANIFEST" | sort -u >"$OFFICIAL_PACKAGE_NAMES"
[ "$(wc -l <"$OFFICIAL_PACKAGE_NAMES")" -gt 0 ] || die "official package manifest is empty"
OFFICIAL_PACKAGES=$(tr '\n' ' ' <"$OFFICIAL_PACKAGE_NAMES")
BUILD_PACKAGES="$OFFICIAL_PACKAGES $CUSTOM_PACKAGES"

tar --zstd -xf "$ARCHIVE_PATH" -C "$WORK_DIR"
IMAGEBUILDER_DIR="$WORK_DIR/openwrt-imagebuilder-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET.Linux-x86_64"
[ -d "$IMAGEBUILDER_DIR" ] || die "unexpected ImageBuilder archive layout"

make -C "$IMAGEBUILDER_DIR" manifest \
	PROFILE="$OPENWRT_PROFILE" \
	PACKAGES="$BUILD_PACKAGES" >"$PLANNED_MANIFEST"

awk '$2 == "-" { print $1 }' "$PLANNED_MANIFEST" | sort -u >"$PLANNED_PACKAGE_NAMES"
[ "$(wc -l <"$PLANNED_PACKAGE_NAMES")" -gt 0 ] || die "planned package manifest is empty"

comm -23 "$OFFICIAL_PACKAGE_NAMES" "$PLANNED_PACKAGE_NAMES" >"$MISSING_OFFICIAL_PACKAGES"
if [ -s "$MISSING_OFFICIAL_PACKAGES" ]; then
	cat "$MISSING_OFFICIAL_PACKAGES" >&2
	die "planned image is missing packages from the official image manifest"
fi

for required_package in \
	luci \
	luci-ssl \
	uhttpd \
	uhttpd-mod-ubus \
	openssh-sftp-server \
	luci-i18n-base-zh-cn; do
	grep -Fxq "$required_package" "$PLANNED_PACKAGE_NAMES" ||
		die "planned image is missing required package: $required_package"
done

make -C "$IMAGEBUILDER_DIR" image \
	PROFILE="$OPENWRT_PROFILE" \
	FILES="$REPO_ROOT/files" \
	PACKAGES="$BUILD_PACKAGES" \
	ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

TARGET_OUTPUT_DIR="$IMAGEBUILDER_DIR/bin/targets/$OPENWRT_TARGET/$OPENWRT_SUBTARGET"

manifests=$(find "$TARGET_OUTPUT_DIR" -maxdepth 1 -type f -name '*.manifest' -print)
[ "$(printf '%s\n' "$manifests" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "expected exactly one package manifest"

awk '$2 == "-" { print $1 }' "$manifests" | sort -u >"$BUILT_PACKAGE_NAMES"
if ! diff -u "$PLANNED_PACKAGE_NAMES" "$BUILT_PACKAGE_NAMES" >"$PACKAGE_DIFF"; then
	cat "$PACKAGE_DIFF" >&2
	die "built package set differs from the ImageBuilder planned manifest"
fi

matches=$(find "$TARGET_OUTPUT_DIR" -type f -name "$EXPECTED_IMAGE" -print)
[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "expected exactly one $EXPECTED_IMAGE"

"$REPO_ROOT/scripts/convert-vmdk.sh" \
	"$matches" \
	"$DIST_DIR" \
	"$ARTIFACT_BASENAME-$OPENWRT_VERSION"
