# TileServer Starter

A self-hosted map tile server for any region of the world.
It serves four map styles from your own hardware.
No internet map service is necessary after you build the data.

Built on [TileServer GL](https://github.com/maptiler/tileserver-gl).
Works well as a map source for TAK clients (ATAK, WinTAK, iTAK) and web maps.

## The four styles

| Style | Description | Data files needed |
|---|---|---|
| `osm` | OpenStreetMap look | `basemap.mbtiles` |
| `topo-light` | Topographic map, light colors, contour lines, hillshade | all three |
| `topo-dark` | Topographic map, dark colors, for night use | all three |
| `overlay` | Transparent overlay with roads and labels, for use over aerial imagery | `basemap.mbtiles` |

## Requirements

- Docker with the Compose plugin
- Disk space for your map data (a small country is 1-2 GB; a US state can be 1-10 GB)

### Disk space

Building needs much more space than the finished files take. Each build
script estimates what its step needs and stops with a clear message if the
drive is too small. As a guide, from a six-state build (NJ, NY, PA, MD, DE,
DC, about 64 square degrees):

| Step | Finished file | Working space needed |
|---|---|---|
| Base map | ~1 GB | ~15 GB |
| Contours | ~2 GB | ~40 GB |
| Hillshade | ~0.5 GB | ~15 GB |

If a build fails anyway and the drive is full, the script says so. Free up
space and run the same command again. Finished downloads are kept and reused.

## Quick start

1. Clone this repository:

   ```bash
   git clone https://github.com/Humble-Helper-96/tileserver-starter.git
   cd tileserver-starter
   ```

2. Build the base map for your region.
   Use an area name from [Geofabrik](https://download.geofabrik.de).
   Example with Switzerland:
   (For a region that spans several Geofabrik areas, such as a group of
   US states, use `build-region.sh` instead. See "Build scripts" below.)

   ```bash
   ./scripts/build-vector.sh switzerland
   ```

3. Build the terrain data for the topo styles.
   Give a bounding box: min-lon, min-lat, max-lon, max-lat.

   ```bash
   ./scripts/build-contours.sh 5.9 45.8 10.5 47.8
   ./scripts/build-hillshade.sh 5.9 45.8 10.5 47.8
   ```

   This step is optional.
   To skip it, copy `.env.example` to `.env` and set `TILESERVER_CONFIG=config-basic.json`.
   Then the server runs only the `osm` and `overlay` styles.
   Note: the server stops if a configured mbtiles file is missing.

4. Start the server:

   ```bash
   docker compose up -d
   ```

5. Open `http://localhost:8080` in a browser.
   You see the style list. Click a style to view the map.

To change the port, copy `.env.example` to `.env` and edit it.

## Build scripts

### `build-vector.sh <area>`

Builds `data/basemap.mbtiles` with [Planetiler](https://github.com/onthegomap/planetiler).
Planetiler downloads the OpenStreetMap extract for the area from Geofabrik.
The output uses the OpenMapTiles schema.
The first run downloads about 1.5 GB of shared world data (coastlines, lakes).
This data stays in `data/sources` for the next runs.
Large areas need more memory: `PLANETILER_MEMORY=8g ./scripts/build-vector.sh germany`.

### `build-contours.sh <min-lon> <min-lat> <max-lon> <max-lat> [m|ft]`

Builds `data/contours.mbtiles` from Copernicus GLO-30 elevation data.
Units are meters by default (minor 20 m, major 100 m).
Use `ft` for feet (minor 40 ft, major 200 ft):

```bash
./scripts/build-contours.sh -150.5 61.0 -149.0 61.6 ft
```

### `build-hillshade.sh <min-lon> <min-lat> <max-lon> <max-lat>`

Builds `data/hillshade.mbtiles` from the same elevation data.

The terrain scripts build a small tool container (GDAL + Tippecanoe) on first run.
Downloaded elevation tiles stay in `data/cache/dem` for reuse.

### `build-region.sh <region-file> [vector] [contours] [hillshade]`

Builds all three data files for a region described in a region file.
A region can cover several Geofabrik extracts, for example several US states.
The script downloads each extract, merges them into one file with Osmium,
and runs Planetiler on the merged file. Then it builds contours and hillshade
for the region's bounding box.

```bash
./scripts/build-region.sh regions/mid-atlantic.env
```

Add step names to run only some steps:

```bash
./scripts/build-region.sh regions/mid-atlantic.env contours hillshade
```

A region file sets these values (see `regions/mid-atlantic.env`):

| Variable | Meaning |
|---|---|
| `REGION_NAME` | Short name for the merged OSM file |
| `GEOFABRIK_AREAS` | Geofabrik paths, for example `north-america/us/new-jersey` |
| `BBOX` | Terrain box: `min-lon min-lat max-lon max-lat` |
| `CONTOUR_UNITS` | `ft` or `m` (default `ft`) |
| `PLANETILER_MEMORY` | Java heap for Planetiler (default `8g`) |

Planetiler output is limited to the region's `BBOX`.

Planetiler also needs three shared inputs (water polygons, Natural Earth,
lake centerlines). The script downloads them to `data/sources` before it runs
Planetiler, so Planetiler itself makes no network calls. Each URL gets several
attempts. If the primary source still fails, the script tries the next URL in
the `SHARED_SOURCES` list at the top of `build-region.sh`. The water polygons
fall back to the North America mirror at `www.osmdata.org`. Files that are
already present are reused. Add more mirrors to that list if a source is
unreliable.

### `merge-osm.sh <output-name> <geofabrik-path> ...`

Downloads Geofabrik extracts to `data/sources/extracts` and merges them into
`data/sources/<output-name>.osm.pbf`. `build-region.sh` calls it for you.

## Bring your own data

You do not have to use the build scripts.
Put your own files in `data/` with these names:

| File | Type | Content |
|---|---|---|
| `data/basemap.mbtiles` | vector | OpenMapTiles schema base map |
| `data/contours.mbtiles` | vector | layers `contours_major` and `contours_minor`, attribute `elev_ft` (feet) or `elev_m` (meters) |
| `data/hillshade.mbtiles` | raster | gray hillshade PNG tiles |

The contour labels read `elev_ft` first, then `elev_m`.
`ft` builds write `elev_ft`. `m` builds write `elev_m`.
Contour files from the [terrain_builder](https://github.com/Humble-Helper-96/terrain_builder)
project carry both attributes. They are a drop-in replacement for
`data/contours.mbtiles`.

## Use with TAK clients

TileServer GL serves rendered raster tiles for each style.
Add a map source in ATAK/WinTAK/iTAK with this URL pattern:

```
http://YOUR_SERVER:8080/styles/topo-light/{z}/{x}/{y}.png
```

Replace `topo-light` with `osm`, `topo-dark`, or `overlay` for the other styles.
For higher resolution screens, use `.../{z}/{x}/{y}@2x.png`.

## Start at boot

See [systemd/README.md](systemd/README.md).

## Changelog

### v0.3

- New `build-region.sh` and `merge-osm.sh`: build all three data files for a
  region that spans several Geofabrik extracts, from one region file.
  First region file: `regions/mid-atlantic.env`.
- `build-region.sh` downloads Planetiler's shared inputs itself, with retries
  and a fallback mirror for the water polygons.
- Planetiler output is limited to the region's bounding box.
- Fix: the tool image failed to build because the GDAL base image lists an
  Apache Arrow apt source whose signing key no longer verifies.
- Build containers now run as the calling user, so files under `data/` are no
  longer owned by root.
- Every build step checks free disk space first and stops with a plain
  message if there is not enough. A step that fails on a full disk says so.
- Fix: terrain intermediates are now tiled BigTIFFs. Before, a large region
  could fill the disk with a feet-converted DEM dozens of times its real size.
- Fix: one-way arrows pointed across the road instead of along it, in all
  four styles.

**Migration:** if you built with an earlier version, files under `data/` are
owned by root. Run `sudo chown -R "$USER:$USER" data` once.

### v0.2

Breaking change: the contour elevation attribute now states its units.
`ft` builds write `elev_ft`. `m` builds write `elev_m`.
Before, both modes wrote one ambiguous `elev` attribute.
This makes contour files from the
[terrain_builder](https://github.com/Humble-Helper-96/terrain_builder)
project a drop-in replacement.

**Migration:** rebuild your `data/contours.mbtiles` with
`./scripts/build-contours.sh`, or replace it with a terrain_builder file.
A contours file from v0.1 still draws contour lines, but the elevation
labels render blank.

### v0.1

First public release.

## Attribution and licenses

- Map data: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL)
- Tile schema and base styles: [OpenMapTiles](https://openmaptiles.org/) (BSD / CC-BY)
- Elevation data: © ESA, [Copernicus DEM GLO-30](https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model)
- Fonts: [Open Sans](https://fonts.google.com/specimen/Open+Sans) (Apache License 2.0)
- Server: [TileServer GL](https://github.com/maptiler/tileserver-gl) (BSD)

Show the OpenStreetMap attribution when you show these maps in public.
The code in this repository is under the MIT license. See [LICENSE](LICENSE).
