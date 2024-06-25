#!/bin/bash

echo $1

# ffmpeg -i ~/Downloads/songs_to_crush_for_radio/Meatball\ Parade.mp3 -map 0:a:0 -ar 4000 -filter:a "highpass=f=200, lowpass=f=3000, volume=1.25" output.ogg


# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 filename start_time seconds"
    exit 1
fi

# Get the filename and seconds from the command-line arguments
filename="$1"
starttime="$2"
seconds="$3"

# Extract base name and extension
base_name="${filename%.*}"
extension="${filename##*.}"

# Construct new filename
new_filename="${base_name}-${seconds}s.ogg"

ffmpeg -i "$filename" -ss "$starttime" -t "$seconds" -map 0:a:0 -ar 4000 -filter:a "highpass=f=200, volume=1.75" "$new_filename"
# crushing to 4k kills the high end. so manualy cut off the low end and boost the overall volume

# Output the result
echo "$new_filename"
