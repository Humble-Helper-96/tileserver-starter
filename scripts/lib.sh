#!/usr/bin/env bash
# Shared functions for the terrain build scripts.
# Do not run this file directly.

TOOLS_IMAGE="tileserver-tools"

# Run the calling script again inside the tool container.
# The container has GDAL and Tippecanoe.
reexec_in_tools() {
    if [ -n "${IN_TOOLS:-}" ]; then
        return 0
    fi
    echo "Building the tool image (first run can take some minutes)..."
    docker build -q -t "$TOOLS_IMAGE" "$REPO_DIR/tools"
    # Run as the calling user so that files under data/ are not owned by
    # root. Host-side steps (curl, rm) must be able to write there too.
    exec docker run --rm \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -e IN_TOOLS=1 \
        -v "$REPO_DIR":/work \
        -w /work \
        "$TOOLS_IMAGE" \
        bash "/work/scripts/$(basename "$0")" "$@"
}

# Download Copernicus GLO-30 DEM tiles for a bounding box.
# Arguments: MIN_LON MIN_LAT MAX_LON MAX_LAT OUT_DIR
# The tiles are 1x1 degree GeoTIFF files.
# Tiles that do not exist (open water) are skipped.
download_dem() {
    local min_lon="$1" min_lat="$2" max_lon="$3" max_lat="$4" out_dir="$5"
    local base_url="https://copernicus-dem-30m.s3.amazonaws.com"
    mkdir -p "$out_dir"

    local lat0 lat1 lon0 lon1
    lat0=$(python3 -c "import math;print(math.floor($min_lat))")
    lat1=$(python3 -c "import math;print(math.floor($max_lat))")
    lon0=$(python3 -c "import math;print(math.floor($min_lon))")
    lon1=$(python3 -c "import math;print(math.floor($max_lon))")

    local lat lon name url dest
    for lat in $(seq "$lat0" "$lat1"); do
        for lon in $(seq "$lon0" "$lon1"); do
            name=$(python3 -c "
lat, lon = $lat, $lon
ns = 'N' if lat >= 0 else 'S'
ew = 'E' if lon >= 0 else 'W'
print(f'Copernicus_DSM_COG_10_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM')
")
            dest="$out_dir/$name.tif"
            if [ -f "$dest" ]; then
                echo "cached: $name"
                continue
            fi
            url="$base_url/$name/$name.tif"
            echo "download: $name"
            if ! curl -sfSL -o "$dest.part" "$url"; then
                echo "  no tile (water area), skipped"
                rm -f "$dest.part"
                continue
            fi
            mv "$dest.part" "$dest"
        done
    done

    if ! ls "$out_dir"/*.tif >/dev/null 2>&1; then
        echo "Error: no DEM tiles found for this bounding box." >&2
        exit 1
    fi
}
