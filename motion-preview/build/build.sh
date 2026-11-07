#!/bin/bash
# build.sh v  -> ../out/qoima_v.mp4
set -e; cd "$(dirname "$0")"; v=$1; NW=${2:-4}
export NODE_PATH=$(npm root -g)
for i in $(seq 0 $((NW-1))); do
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 seg_${v}_$i.mp4 2>/dev/null | head -1)
  if [ "${d%%.*}" = "$((60/NW))" ] && [ -z "${d##*.0*}" ]; then echo "segment $i ok, reuse"; else node render.js $v $i $NW & fi
done; wait
rm -f list_$v.txt; for i in $(seq 0 $((NW-1))); do echo "file 'seg_${v}_$i.mp4'" >> list_$v.txt; done
ffmpeg -y -v error -f concat -safe 0 -i list_$v.txt -c copy video_$v.mp4
# two-pass loudnorm to -14 LUFS
J=$(ffmpeg -v info -i ${v}_mix_raw.wav -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | sed -n '/^{/,/^}/p')
MI=$(echo "$J"|python3 -c "import json,sys;d=json.load(sys.stdin);print(d['input_i'])"); MTP=$(echo "$J"|python3 -c "import json,sys;d=json.load(sys.stdin);print(d['input_tp'])")
ML=$(echo "$J"|python3 -c "import json,sys;d=json.load(sys.stdin);print(d['input_lra'])"); MT=$(echo "$J"|python3 -c "import json,sys;d=json.load(sys.stdin);print(d['input_thresh'])"); OFF=$(echo "$J"|python3 -c "import json,sys;d=json.load(sys.stdin);print(d['target_offset'])")
mkdir -p ../out
ffmpeg -y -v error -i video_$v.mp4 -i ${v}_mix_raw.wav -af "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$MI:measured_TP=$MTP:measured_LRA=$ML:measured_thresh=$MT:offset=$OFF:linear=true,aresample=48000" -map 0:v -map 1:a -c:v copy -c:a aac -b:a 256k -ar 48000 -movflags +faststart -shortest ../out/qoima_$v.mp4
echo built ../out/qoima_$v.mp4
