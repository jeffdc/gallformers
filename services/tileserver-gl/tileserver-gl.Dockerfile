FROM maptiler/tileserver-gl:latest
# Run the build_boundaries.sh script to create the boundaries.mbtiles file
# The below assumes that the output file is named boundaries.mbtiles and is 
# in the same directory where the generation script is run.
COPY boundaries.mbtiles boundaries.mbtiles
