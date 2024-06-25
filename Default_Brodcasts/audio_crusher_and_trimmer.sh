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

ffmpeg -i "$filename" -ss "$starttime" -t "$seconds" -map 0:a:0 -ar 4000 -filter:a "highpass=f=200, volume=1.75" "$new_filename"
# crushing to 4k kills the high end. so manualy cut off the low end and boost the overall volume

# Output the result
echo "$new_filename"
