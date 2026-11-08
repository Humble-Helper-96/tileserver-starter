#!/usr/bin/env bash
# Build all map data for one region from a region file.
# A region file lists Geofabrik extracts, a terrain bounding box, and options.
# See regions/mid-atlantic.env for an example.
#
# Usage:
#   ./scripts/build-region.sh <region-file> [step ...]
#
# Steps (default: all three, in this order):
#   vector     download and merge the OSM extracts, then run Planetiler
#              -> data/basemap.mbtiles
#   contours   -> data/contours.mbtiles
#   hillshade  -> data/hillshade.mbtiles
#
# Example: rebuild only the contours
#   ./scripts/build-region.sh regions/mid-atlantic.env contours

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <region-file> [vector] [contours] [hillshade]" >&2
    exit 1
fi

REGION_FILE="$1"
shift
if [ ! -f "$REGION_FILE" ]; then
    echo "Error: region file not found: $REGION_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$REGION_FILE"

: "${REGION_NAME:?REGION_NAME is not set in $REGION_FILE}"
: "${GEOFABRIK_AREAS:?GEOFABRIK_AREAS is not set in $REGION_FILE}"
: "${BBOX:?BBOX is not set in $REGION_FILE}"
CONTOUR_UNITS="${CONTOUR_UNITS:-ft}"
PLANETILER_MEMORY="${PLANETILER_MEMORY:-8g}"

# shellcheck disable=SC2206
BBOX_ARGS=($BBOX)
if [ ${#BBOX_ARGS[@]} -ne 4 ]; then
    echo "Error: BBOX must have 4 numbers: min-lon min-lat max-lon max-lat" >&2
    exit 1
fi
BBOX_CSV="$(IFS=,; echo "${BBOX_ARGS[*]}")"

STEPS=("$@")
if [ ${#STEPS[@]} -eq 0 ]; then
    STEPS=(vector contours hillshade)
fi
for step in "${STEPS[@]}"; do
    case "$step" in
        vector|contours|hillshade) ;;
        *) echo "Error: unknown step '$step'" >&2; exit 1 ;;
    esac
done

run_vector() {
    # shellcheck disable=SC2086
    "$REPO_DIR/scripts/merge-osm.sh" "$REGION_NAME" $GEOFABRIK_AREAS

    echo "Planetiler: build data/basemap.mbtiles (Java heap $PLANETILER_MEMORY)"

    # Planetiler also needs three shared inputs. When all three are already
    # in data/sources, skip --download so Planetiler makes no network calls.
    # If a download keeps failing, fetch the file by hand into data/sources
    # (see the README) and run the step again.
    local sources="$REPO_DIR/data/sources"
    local download_flag="--download"
    if [ -s "$sources/water-polygons-split-3857.zip" ] \
        && [ -s "$sources/natural_earth_vector.sqlite.zip" ] \
        && [ -s "$sources/lake_centerline.shp.zip" ]; then
        echo "Shared inputs found in data/sources: skipping Planetiler downloads."
        download_flag=""
    fi

    # --bounds limits the output to the region box. Without it Planetiler
    # takes the bounds from the merged OSM data, which can be far larger
    # (extracts include complete ways and relations that reach outside).
    # shellcheck disable=SC2086
    docker run --rm \
        -e JAVA_TOOL_OPTIONS="-Xmx$PLANETILER_MEMORY" \
        -v "$REPO_DIR/data":/data \
        ghcr.io/onthegomap/planetiler:latest \
        $download_flag \
        --force \
        --osm-path="/data/sources/$REGION_NAME.osm.pbf" \
        --bounds="$BBOX_CSV" \
        --tmpdir=/data/tmp \
        --output=/data/basemap.mbtiles
}

run_contours() {
    "$REPO_DIR/scripts/build-contours.sh" "${BBOX_ARGS[@]}" "$CONTOUR_UNITS"
}

run_hillshade() {
    "$REPO_DIR/scripts/build-hillshade.sh" "${BBOX_ARGS[@]}"
}

echo "Region: $REGION_NAME"
echo "Steps:  ${STEPS[*]}"
for step in "${STEPS[@]}"; do
    start=$(date +%s)
    echo
    echo "=== $step ==="
    "run_$step"
    end=$(date +%s)
    echo "=== $step finished in $(( (end - start) / 60 )) min ==="
done

echo
echo "Output files:"
ls -lh "$REPO_DIR"/data/*.mbtiles 2>/dev/null || echo "(none)"
