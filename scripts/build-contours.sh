#!/usr/bin/env bash
# Build contour line vector tiles for one region.
# The script downloads Copernicus GLO-30 elevation data.
# The output file is data/contours.mbtiles.
#
# Usage:
#   ./scripts/build-contours.sh <min-lon> <min-lat> <max-lon> <max-lat> [m|ft]
#
# The last argument selects the units:
#   m  = meters. Minor interval 20 m, major interval 100 m. This is the default.
#   ft = feet. Minor interval 40 ft, major interval 200 ft.
#
# Output tile schema:
#   Layer "contours_major": lines, attribute "elev" (number), zoom 8-14.
#   Layer "contours_minor": lines, attribute "elev" (number), zoom 11-14.
# The "elev" value is in the selected units.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$REPO_DIR/scripts/lib.sh"

if [ $# -lt 4 ] || [ $# -gt 5 ]; then
    echo "Usage: $0 <min-lon> <min-lat> <max-lon> <max-lat> [m|ft]" >&2
    exit 1
fi

reexec_in_tools "$@"

MIN_LON="$1" MIN_LAT="$2" MAX_LON="$3" MAX_LAT="$4"
UNITS="${5:-m}"

case "$UNITS" in
    m)  MINOR=20; MAJOR=100 ;;
    ft) MINOR=40; MAJOR=200 ;;
    *)  echo "Error: units must be 'm' or 'ft'." >&2; exit 1 ;;
esac

DEM_DIR="$REPO_DIR/data/cache/dem"
WORK_DIR="$REPO_DIR/data/cache/contours"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "Step 1/5: download elevation tiles"
download_dem "$MIN_LON" "$MIN_LAT" "$MAX_LON" "$MAX_LAT" "$DEM_DIR"

echo "Step 2/5: merge and clip the elevation data"
gdalbuildvrt -q -te "$MIN_LON" "$MIN_LAT" "$MAX_LON" "$MAX_LAT" \
    "$WORK_DIR/dem.vrt" "$DEM_DIR"/*.tif

DEM_INPUT="$WORK_DIR/dem.vrt"
if [ "$UNITS" = "ft" ]; then
    echo "Step 2b: convert elevation values to feet"
    gdal_calc.py -A "$WORK_DIR/dem.vrt" --calc="A*3.28084" \
        --outfile="$WORK_DIR/dem_ft.tif" \
        --co COMPRESS=DEFLATE --quiet
    DEM_INPUT="$WORK_DIR/dem_ft.tif"
fi

echo "Step 3/5: compute contour lines (interval $MINOR $UNITS)"
gdal_contour -q -a elev -i "$MINOR" "$DEM_INPUT" "$WORK_DIR/contours.gpkg" -nln contour

echo "Step 4/5: split major and minor contours"
ogr2ogr -f GeoJSONSeq "$WORK_DIR/major.json" "$WORK_DIR/contours.gpkg" \
    -dialect SQLITE -sql "SELECT elev, geom FROM contour WHERE CAST(elev AS INTEGER) % $MAJOR = 0"
ogr2ogr -f GeoJSONSeq "$WORK_DIR/minor.json" "$WORK_DIR/contours.gpkg" \
    -dialect SQLITE -sql "SELECT elev, geom FROM contour WHERE CAST(elev AS INTEGER) % $MAJOR <> 0"

echo "Step 5/5: build the vector tiles"
tippecanoe -q -f -o "$WORK_DIR/major.mbtiles" -l contours_major \
    -Z8 -z14 -y elev --drop-densest-as-needed \
    -A "Copernicus DEM (c) ESA" "$WORK_DIR/major.json"
tippecanoe -q -f -o "$WORK_DIR/minor.mbtiles" -l contours_minor \
    -Z11 -z14 -y elev --drop-densest-as-needed \
    -A "Copernicus DEM (c) ESA" "$WORK_DIR/minor.json"
tile-join -f -o "$REPO_DIR/data/contours.mbtiles" -n "Contours ($UNITS)" \
    "$WORK_DIR/major.mbtiles" "$WORK_DIR/minor.mbtiles"

rm -rf "$WORK_DIR"
echo "Done. Output: data/contours.mbtiles (units: $UNITS)"
