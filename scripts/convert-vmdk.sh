#!/bin/sh

set -eu

die() {
	printf '%s\n' "error: $*" >&2
	exit 1
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

[ "$#" -eq 3 ] || die "usage: $0 INPUT.img.gz OUTPUT_DIR OUTPUT_BASENAME"

INPUT_IMAGE=$1
OUTPUT_DIR=$2
OUTPUT_BASENAME=$3

[ -f "$INPUT_IMAGE" ] || die "input image not found: $INPUT_IMAGE"
[ -s "$INPUT_IMAGE" ] || die "input image is empty: $INPUT_IMAGE"

case "$OUTPUT_BASENAME" in
	''|*/*) die "OUTPUT_BASENAME must be a non-empty file name" ;;
esac

for command_name in gzip qemu-img sha256sum mktemp; do
	need_command "$command_name"
done

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(CDPATH='' cd -- "$OUTPUT_DIR" && pwd)
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.convert.XXXXXX")
trap 'rm -rf -- "$WORK_DIR"' EXIT HUP INT TERM

IMG_GZ_NAME="$OUTPUT_BASENAME.img.gz"
RAW_IMG_NAME="$OUTPUT_BASENAME.img"
VMDK_NAME="$OUTPUT_BASENAME.vmdk"
CHECKSUM_NAME="$OUTPUT_BASENAME.sha256sums"

cp -- "$INPUT_IMAGE" "$WORK_DIR/$IMG_GZ_NAME"
gzip -t "$WORK_DIR/$IMG_GZ_NAME"
gzip -dc "$WORK_DIR/$IMG_GZ_NAME" >"$WORK_DIR/$RAW_IMG_NAME"
[ -s "$WORK_DIR/$RAW_IMG_NAME" ] || die "decompressed raw image is empty"

raw_info=$(qemu-img info --output=json "$WORK_DIR/$RAW_IMG_NAME")
printf '%s\n' "$raw_info" | grep -Eq '"format"[[:space:]]*:[[:space:]]*"raw"' ||
	die "qemu-img did not recognize the decompressed image as raw"

qemu-img convert -f raw -O vmdk "$WORK_DIR/$RAW_IMG_NAME" "$WORK_DIR/$VMDK_NAME"
[ -s "$WORK_DIR/$VMDK_NAME" ] || die "converted VMDK is empty"

vmdk_info=$(qemu-img info --output=json "$WORK_DIR/$VMDK_NAME")
printf '%s\n' "$vmdk_info" | grep -Eq '"format"[[:space:]]*:[[:space:]]*"vmdk"' ||
	die "qemu-img did not recognize the converted image as VMDK"

(
	cd "$WORK_DIR"
	sha256sum "$IMG_GZ_NAME" "$RAW_IMG_NAME" "$VMDK_NAME" >"$CHECKSUM_NAME"
)

for artifact in "$IMG_GZ_NAME" "$RAW_IMG_NAME" "$VMDK_NAME" "$CHECKSUM_NAME"; do
	mv -f -- "$WORK_DIR/$artifact" "$OUTPUT_DIR/$artifact"
done

printf '%s\n' \
	"created: $OUTPUT_DIR/$IMG_GZ_NAME" \
	"created: $OUTPUT_DIR/$RAW_IMG_NAME" \
	"created: $OUTPUT_DIR/$VMDK_NAME" \
	"created: $OUTPUT_DIR/$CHECKSUM_NAME"
