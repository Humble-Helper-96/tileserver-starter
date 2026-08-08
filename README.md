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

## Quick start

1. Clone this repository:

   ```bash
   git clone https://github.com/Humble-Helper-96/tileserver-starter.git
   cd tileserver-starter
   ```

2. Build the base map for your region.
   Use an area name from [Geofabrik](https://download.geofabrik.de).
   Example with Switzerland:

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

## Bring your own data

You do not have to use the build scripts.
Put your own files in `data/` with these names:

| File | Type | Content |
|---|---|---|
| `data/basemap.mbtiles` | vector | OpenMapTiles schema base map |
| `data/contours.mbtiles` | vector | layers `contours_major` and `contours_minor`, attribute `elev` |
| `data/hillshade.mbtiles` | raster | gray hillshade PNG tiles |

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

## Attribution and licenses

- Map data: © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL)
- Tile schema and base styles: [OpenMapTiles](https://openmaptiles.org/) (BSD / CC-BY)
- Elevation data: © ESA, [Copernicus DEM GLO-30](https://spacedata.copernicus.eu/collections/copernicus-digital-elevation-model)
- Fonts: [Open Sans](https://fonts.google.com/specimen/Open+Sans) (Apache License 2.0)
- Server: [TileServer GL](https://github.com/maptiler/tileserver-gl) (BSD)

Show the OpenStreetMap attribution when you show these maps in public.
The code in this repository is under the MIT license. See [LICENSE](LICENSE).
