# 3dmaps

# Table of contents
 - [Dependencies](#dependencies)
 - [Setup](#setup)
 - [Todos](#todos)

# Dependencies
- GDAL
- GLFW3
- GLAD generated from https://gen.glad.sh/

# Setup
Get OSM data for region from: https://download.geofabrik.de/europe/united-kingdom/england/cumbria.html
Get topography data from: https://opentopography.org/
N.B Ensure the topography data fully covers the OSM data exported.

zig build run -- <filename>


./zig-out/bin/get_textures --output-dir output/ --zoom 12 --bounds 54.5,-3.1,54.7,-2.9

### Todos
 - ..

License
----

MIT
