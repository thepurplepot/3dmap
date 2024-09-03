# 3dmaps
Cross platform 3D terrain renderer from real world data.
![Screenshot of the application rendering a 3D map of the Lake District](res/ss.png)

# Table of contents
 - [Dependencies](#dependencies)
 - [Setup](#setup)
 - [Todos](#todos)

# Dependencies
- GDAL
- GLFW3
- OpenGL 4.0

# Setup
Get OSM data for region from: https://download.geofabrik.de/europe/united-kingdom/england/cumbria.html
Get topography data from: https://opentopography.org/
N.B Ensure the topography data fully covers the OSM data exported.

To build app and texture fetcher run:
``` bash
zig build
```

Then run this to fetch the textures with the desired zoom level and bounds (zoom = 12 works well).
``` bash
./zig-out/bin/get_textures --output-dir output/ --zoom 12 --bounds 54.5,-3.1,54.7,-2.9
```

Finaly run the app with:
```bash
zig build -Doptimize=ReleaseSafe run
```
### Todos
 - GPX plotting
 - Overlay OSM data

License
----

MIT
