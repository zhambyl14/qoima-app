#!/bin/bash
# review.sh v "t1 t2 ..." -> ../shots/review_v.jpg (frames decoded from final MP4) + ffprobe
cd "$(dirname "$0")"; v=$1; f=../out/qoima_$v.mp4
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt,sample_rate,channels,bit_rate,duration -show_entries format=duration,size -of compact $f
ffmpeg -v info -i $f -map 0:a -af ebur128=peak=true -f null - 2>&1 | grep -E "^\s+(I:|LRA:|Peak:)" | tail -3
mkdir -p rev_$v; rm -f rev_$v/*.png; i=0
for t in $2; do ffmpeg -v error -ss $t -i $f -frames:v 1 -vf scale=270:480 rev_$v/$(printf %02d $i).png; i=$((i+1)); done
ffmpeg -y -v error -pattern_type glob -i "rev_$v/*.png" -vf tile=8x$(( (i+7)/8 )) ../shots/review_$v.jpg && echo sheet ok
