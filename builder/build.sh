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
: "${IMAGE_PACKAGES:?missing IMAGE_PACKAGES}"
: "${PACKAGE_MANAGER_CALL_UPSTREAM_SHA256:?missing PACKAGE_MANAGER_CALL_UPSTREAM_SHA256}"

printf '%s\n' "$OPENWRT_RELEASE_SERIES" | grep -Eq '^[0-9]+\.[0-9]+$' ||
	die "invalid release series: $OPENWRT_RELEASE_SERIES"

case "$ROOTFS_PARTSIZE" in
	*[!0-9]*|'') die "ROOTFS_PARTSIZE must be a positive integer" ;;
	0) die "ROOTFS_PARTSIZE must be greater than zero" ;;
esac

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

verify_luci_overlay() {
	feeds_file=$1
	overlay="$REPO_ROOT/files/usr/libexec/package-manager-call"
	official="$WORK_DIR/package-manager-call.official"
	expected="$WORK_DIR/package-manager-call.expected"

	[ -f "$overlay" ] || die "missing LuCI overlay: $overlay"
	[ -x "$overlay" ] || die "LuCI overlay is not executable: $overlay"

	luci_commit=$(sed -n 's#^src-git luci .*\^\([0-9a-f][0-9a-f]*\)$#\1#p' "$feeds_file")
	[ "$(printf '%s\n' "$luci_commit" | sed '/^$/d' | wc -l)" -eq 1 ] ||
		die "unable to identify exactly one LuCI commit"

	fetch "https://raw.githubusercontent.com/openwrt/luci/$luci_commit/applications/luci-app-package-manager/root/usr/libexec/package-manager-call" "$official"

	official_hash=$(sha256sum "$official" | awk '{print $1}')
	[ "$official_hash" = "$PACKAGE_MANAGER_CALL_UPSTREAM_SHA256" ] ||
		die "official package-manager-call changed ($official_hash); Phase 3 review required"

	[ "$(grep -Fxc '						action="add"' "$official")" -eq 1 ] ||
		die "official package-manager-call install mapping has an unexpected structure"

	sed 's/^\(\t*\)action="add"$/\1action="add --allow-untrusted"/' "$official" >"$expected"
	cmp -s "$expected" "$overlay" ||
		die "LuCI overlay contains changes beyond the reviewed --allow-untrusted addition"
}

OPENWRT_VERSION=$(resolve_version)

if [ "${1:-}" = "--resolve-version" ]; then
	printf '%s\n' "$OPENWRT_VERSION"
	exit 0
fi

[ "$#" -eq 0 ] || die "usage: $0 [--resolve-version]"

for command_name in curl sha256sum awk sed grep sort tail tar make find cmp mktemp; do
	need_command "$command_name"
done

TARGET_URL="$OPENWRT_DOWNLOAD_BASE/$OPENWRT_VERSION/targets/$OPENWRT_TARGET/$OPENWRT_SUBTARGET"
IMAGEBUILDER_ARCHIVE="openwrt-imagebuilder-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET.Linux-x86_64.tar.zst"
EXPECTED_IMAGE="openwrt-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET-$OPENWRT_PROFILE-$ROOTFS_FILESYSTEM-$IMAGE_FLAVOR.img.gz"

CACHE_ROOT="$REPO_ROOT/.cache"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$CACHE_ROOT" "$DIST_DIR"
WORK_DIR=$(mktemp -d "$CACHE_ROOT/imagebuilder.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT HUP INT TERM

SHA256SUMS="$WORK_DIR/sha256sums"
ARCHIVE_PATH="$WORK_DIR/$IMAGEBUILDER_ARCHIVE"
FEEDS_BUILDINFO="$WORK_DIR/feeds.buildinfo"

fetch "$TARGET_URL/sha256sums" "$SHA256SUMS"
fetch "$TARGET_URL/$IMAGEBUILDER_ARCHIVE" "$ARCHIVE_PATH"
fetch "$TARGET_URL/feeds.buildinfo" "$FEEDS_BUILDINFO"

expected_hash=$(awk -v name="$IMAGEBUILDER_ARCHIVE" '$2 == name || $2 == "*" name { print $1 }' "$SHA256SUMS")
[ "$(printf '%s\n' "$expected_hash" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "ImageBuilder has zero or multiple checksum entries"
actual_hash=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
[ "$actual_hash" = "$expected_hash" ] || die "ImageBuilder SHA-256 verification failed"

verify_luci_overlay "$FEEDS_BUILDINFO"

tar --zstd -xf "$ARCHIVE_PATH" -C "$WORK_DIR"
IMAGEBUILDER_DIR="$WORK_DIR/openwrt-imagebuilder-$OPENWRT_VERSION-$OPENWRT_TARGET-$OPENWRT_SUBTARGET.Linux-x86_64"
[ -d "$IMAGEBUILDER_DIR" ] || die "unexpected ImageBuilder archive layout"

make -C "$IMAGEBUILDER_DIR" image \
	PROFILE="$OPENWRT_PROFILE" \
	FILES="$REPO_ROOT/files" \
	PACKAGES="$IMAGE_PACKAGES" \
	ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"

TARGET_OUTPUT_DIR="$IMAGEBUILDER_DIR/bin/targets/$OPENWRT_TARGET/$OPENWRT_SUBTARGET"

manifests=$(find "$TARGET_OUTPUT_DIR" -maxdepth 1 -type f -name '*.manifest' -print)
[ "$(printf '%s\n' "$manifests" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "expected exactly one package manifest"

for required_package in $IMAGE_PACKAGES; do
	grep -Eq "^${required_package}[[:space:]]+-[[:space:]]+" "$manifests" ||
		die "required package missing from image manifest: $required_package"
done

matches=$(find "$TARGET_OUTPUT_DIR" -type f -name "$EXPECTED_IMAGE" -print)
[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)" -eq 1 ] ||
	die "expected exactly one $EXPECTED_IMAGE"

"$REPO_ROOT/scripts/convert-vmdk.sh" \
	"$matches" \
	"$DIST_DIR" \
	"$ARTIFACT_BASENAME-$OPENWRT_VERSION"
