#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 filename start_time seconds"
    exit 1
fi

filename="$1"
starttime="$2"
seconds="$3"

base_name="${filename%.*}"
new_filename="${base_name}-${seconds}s.ogg"

ffmpeg -i "$filename"   \
    -ss "$starttime"    \
    -t "$seconds"       \
    -map 0:a:0 -ac 1    \
    -filter:a "highpass=f=200" -q:a 2 -ar 4000    \
    "$new_filename"
# dynaudnorm reccomended by https://superuser.com/a/323127

# Output the result
echo "$new_filename"
