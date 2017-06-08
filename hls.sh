#!/bin/bash
#
# A very simple BASH script to take an input video and split it down into Segments 
# before creating an M3U8 Playlist, allowing the file to be served using HLS
#
#

######################################################################################
#
# Copyright (c) 2013, Ben Tasker
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# 
#   Redistributions in binary form must reproduce the above copyright notice, this
#   list of conditions and the following disclaimer in the documentation and/or
#   other materials provided with the distribution.
# 
#   Neither the name of Ben Tasker nor the names of his
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 
######################################################################################

set -x

# Basic config
OUTPUT_DIRECTORY=${OUTPUT_DIRECTORY:-'./output'}

# Change this if you want to specify a path to use a specific version of FFMPeg
FFMPEG=${FFMPEG:-'ffmpeg'}

# Number of threads which will be used for transcoding. With newer FFMPEGs and x264
# encoders "0" means "optimal". This is normally the number of CPU cores.
NUMTHREADS=${NUMTHREADS:-"0"}

# Video codec for the output video. Will be used as an value for the -vcodec argument
VIDEO_CODEC=${VIDEO_CODEC:-"libx264"}

# Audio codec for the output video. Will be used as an value for the -acodec argument
AUDIO_CODEC=${AUDIO_CODEC:-"libfdk_aac"}

# Additional flags for ffmpeg
FFMPEG_FLAGS=${FFMPEG_FLAGS:-""}

# If the input is a live stream (i.e. linear video) this should be 1
LIVE_STREAM=${LIVE_STREAM:-0}

# No Audio codec is expected in output video, this should be 1. Will apply the -an argument and remove -acodec argument
VIDEO_ONLY=${VIDEO_ONLY:-0}
TLM_PREFIX="_TLM.m3u8"

# Video bitrates to use in output (comma seperated list if you want to create an adaptive stream.)
# leave null to use the input bitrate
OP_BITRATES=${OP_BITRATES:-''}

# Determines whether the processing for adaptive streams should run sequentially or not
NO_FORK=${NO_FORK:-0}

# Input folder where video will be downloaded
INPUT_FOLDER=${INPUT_FOLDER:-"./input"}

# Check whether input file is an URL or not
URL_INPUT_FILE="0"

# Lets put our functions here

## Output the script's CLI Usage
#
#
function print_usage(){

cat << EOM
HTTP Live Stream Creator
Version 1

Copyright (C) 2013 B Tasker, D Atanasov
Released under BSD 3 Clause License
See LICENSE


Usage: $0 -[lf] [-c segmentcount] -i [inputfile] -s [segmentlength(seconds)] -o [outputdir] -b [bitrates]  [-p filename]

	-i	Input file. In case of a URL file will be downloaded automatically.
	-s	Segment length (seconds)
	-o	Output directory (default: ./output)
	-l	Input is a live stream
	-c	Number of segments to include in playlist (live streams only) - 0 is no limit
	-b	Output video Bitrates (comma seperated list for adaptive streams)
	-f	Foreground encoding only (don't fork the encoding processes into the background - adaptive non-live streams only)
	-p	Playlist filename
	-t	Segment filename prefix
	-S	Segment directory name (default none)
	-e	Encrypt the HLS segments (default none)

Deprecated Legacy usage:
	$0 inputfile segmentlength(seconds) [outputdir='./output']

Example :
$0 -i "http://download.wavetlan.com/SVV/Media/HTTP/MP4/ConvertedFiles/MediaCoder/MediaCoder_test1_1m9s_AVC_VBR_256kbps_640x480_24fps_MPEG2Layer3_CBR_160kbps_Stereo_22050Hz.mp4" -s 10 -b 28,64,128,256 -f

EOM

exit

}


function addstreamtype() {
playlist_name="$1"
live_stream="$2"

PLATFORM=`uname -s`

if [ "$live_stream" == "1" ]
then
    if [ "$PLATFORM" == "Darwin" ]; then
        sed -e 's/#EXT-X-MEDIA-SEQUENCE\(.*\)/#EXT-X-MEDIA-SEQUENCE\1\'$'\n#EXT-X-PLAYLIST-TYPE:LIVE/g' "$playlist_name"
    elif [ "$PLATFORM" == "Linux" ]; then
        sed -i '/#EXT-X-MEDIA-SEQUENCE.*/a #EXT-X-PLAYLIST-TYPE:LIVE' "$playlist_name"
    fi
else
    if [ "$PLATFORM" == "Darwin" ]; then
        sed -e 's/#EXT-X-MEDIA-SEQUENCE\(.*\)/#EXT-X-MEDIA-SEQUENCE\1\'$'\n#EXT-X-PLAYLIST-TYPE:VOD/g' "$playlist_name"
    elif [ "$PLATFORM" == "Linux" ]; then
        sed -i '/#EXT-X-MEDIA-SEQUENCE.*/a #EXT-X-PLAYLIST-TYPE:VOD' "$playlist_name"
    fi
fi



}


function createStream(){
# For VoD and single bitrate streams the variables we need will exist in Global scope.
# for live adaptive streams though, that won't be the case, so we need to take them as arguments
# Some are global though, so we'll leave those as is

playlist_name="$1"
output_name="$2"
bitrate="$3"
infile="$4"

if [ "$VIDEO_ONLY" == "1" ]
then
$FFMPEG -i "$infile" \
    -loglevel error -y \
    -an \
    -vcodec "$VIDEO_CODEC" \
    -threads "$NUMTHREADS" \
    -map 0 \
    -flags \
    -global_header \
    -f segment \
    -segment_list "$playlist_name" \
    -segment_time "$SEGLENGTH" \
    -segment_format mpeg_ts \
    $bitrate \
    $FFMPEG_ADDITIONAL \
    $FFMPEG_FLAGS \
    $output_name
else
$FFMPEG -i "$infile" \
    -loglevel error -y \
    -vcodec "$VIDEO_CODEC" \
    -acodec "$AUDIO_CODEC" \
    -threads "$NUMTHREADS" \
    -map 0 \
    -flags \
    -global_header \
    -f segment \
    -segment_list "$playlist_name" \
    -segment_time "$SEGLENGTH" \
    -segment_format mpeg_ts \
    $bitrate \
    $FFMPEG_ADDITIONAL \
    $FFMPEG_FLAGS \
    $output_name
fi
}


function createVariantPlaylist(){
playlist_name="$1"
echo "#EXTM3U" > "$playlist_name"
}


function appendVariantPlaylistentry(){
playlist_name=$1
playlist_path=$2
playlist_bw=$3

cat << EOM >> "$playlist_name"
#EXT-X-STREAM-INF:BANDWIDTH=$playlist_bw
$playlist_path
EOM

}

function createAudioEntry(){
    video_playlist=$1
    codec=$2
    lang=$3

    if [ "$lang" == "" ]
    then
        lang="und"
    fi
    audio_path=$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_Audio_$(tr '[:lower:]' '[:upper:]' <<< ${lang:0:1})${lang:1}_`echo $codec | awk '{print toupper($0)}'`
    lang_name=`echo $lang | awk '{print toupper($0)}'`

    mkdir -p $audio_path

    #Encode each TS to AAC
    cp $video_playlist $audio_path/prog_index.m3u8
    sed -i.bak 's/\(.*\).ts/\1.aac/' "${audio_path}/prog_index.m3u8" && rm -f ${audio_path}/prog_index.m3u8.bak

    #Replace each TS by AAC in Media Playlist
    for seg in `cat $video_playlist  | awk '/#EXTINF:/{getline;print}'`
    do
        mkdir -p $audio_path/$(dirname "$seg")
        $FFMPEG -i $(dirname "$video_playlist")/$seg -acodec copy "${audio_path}/${seg%.ts*}.aac"
    done

    sed -i.bak 's/.*'${audio_path##*/}'\/prog_index.m3u8.*//' $OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX} && rm -f $OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}.bak

    #Add Alt Audio Entry into TLM && Add "AUDIO" Attribute for each video media playlist WITHOUT "AUDIO="
cat << EOM >> "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}"

#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="$codec",LANGUAGE="$lang",NAME="$lang_name",AUTOSELECT=YES,DEFAULT=NO,URI="${audio_path##*/}/prog_index.m3u8"
EOM

}


function appendAudioAttrForVideoPlayListEntry() {
    codec=$1
    awk '{if (/EXT-X-STREAM-INF/ && !/AUDIO=/) {$0=$0",AUDIO=\"'$codec'\""}; print}' "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}" >> "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}.tmp" && \
    mv "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}.tmp" "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}"
}


function awaitCompletion(){
# Monitor the encoding pids for their completion status
while [ ${#PIDS[@]} -ne 0 ]; do
    # Calculate the length of the array
    pid_length=$((${#PIDS[@]} - 1))

    # Check each PID in the array
    for i in `seq 0 $pid_length`
    do
	  # Test whether the pid is still active
	  if ! kill -0 ${PIDS[$i]} 2> /dev/null
	  then
		echo "Encoding for bitrate ${BITRATE_PROCESSES[$i]}k completed"

		if [ "$LIVE_STREAM" == "1" ] && [ `grep 'EXT-X-ENDLIST' "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${BITRATE_PROCESSES[$i]}.m3u8" | wc -l ` == "0" ]
		then
		    # Correctly terminate the manifest. See HLS-15 for info on why
		    echo "#EXT-X-ENDLIST" >> "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${BITRATE_PROCESSES[$i]}.m3u8"
		fi

                addstreamtype "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}_${BITRATE_PROCESSES[$i]}.m3u8" "$LIVE_STREAM"

		unset BITRATE_PROCESSES[$i]
		unset PIDS[$i]
	  fi
    done

    # remove any nulls
    PIDS=("${PIDS[@]}") 
    BITRATE_PROCESSES=("${BITRATE_PROCESSES[@]}")

    sleep 1
done
}

function encrypt(){
# Encrypt the generated segments with AES-128 bits

    KEY_FILE="$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}.key"

    openssl rand 16 > $KEY_FILE
    ENCRYPTION_KEY=$(cat $KEY_FILE | hexdump -e '16/1 "%02x"')

    count=0
    for file in $(ls ${OUTPUT_DIRECTORY}/*.ts | cut -f3 -d '/')
    do
        ENC_FILENAME="$OUTPUT_DIRECTORY/${SEGMENT_PREFIX}_enc_${count}".ts

	INIT_VECTOR=$(printf '%032x' $count)
	openssl aes-128-cbc -e -in $OUTPUT_DIRECTORY/$file -out $ENC_FILENAME -nosalt -iv $INIT_VECTOR -K $ENCRYPTION_KEY

        # Move encrypted file to the original filename, so that the m3u8 file does not have to be changed
        mv $ENC_FILENAME ${OUTPUT_DIRECTORY}/$file

        count=$((count+1))
    done

    # Insert the KEY at the 5'th line in the m3u8 file
    sed -i "5i #EXT-X-KEY:METHOD=AES-128,URI="${PLAYLIST_PREFIX}.key "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}.m3u8"
}

## Input file checker
# Dowload input file if needed
#
function input_file_checker() {
  inputfile=$1

  wget -q --spider $inputfile
  if [ "$?" == 0 ]
  then
      FILENAME=`basename $inputfile`

      mkdir -p $INPUT_FOLDER

      if [ ! -e "$INPUT_FOLDER/$FILENAME" ]
      then
          wget -P $INPUT_FOLDER $inputfile
      fi
      
      URL_INPUT_FILE="1"

      INPUTFILE="$INPUT_FOLDER/$FILENAME"
  else
      if [ ! -e "$inputfile" ] #input file is a file wich does not exist
      then
          print_usage
          exit 1
      fi
  fi
}

# This is used internally, if the user wants to specify their own flags they should be
# setting FFMPEG_FLAGS
FFMPEG_ADDITIONAL=''
LIVE_SEGMENT_COUNT=0
VIDEO_ONLY=0
IS_FIFO=0
TMPDIR=${TMPDIR:-"/tmp"}
MYPID=$$
# Get the input data

# This exists to maintain b/c
LEGACY_ARGS=1

# If even one argument is supplied, switch off legacy argument style
while getopts "i:o:s:c:b:p:t:S:lfem" flag
do
	LEGACY_ARGS=0
        case "$flag" in
                i) INPUTFILE="$OPTARG";;
                o) OUTPUT_DIRECTORY="$OPTARG";;
                s) SEGLENGTH="$OPTARG";;
		l) LIVE_STREAM=1;;
		m) VIDEO_ONLY=1;;
		c) LIVE_SEGMENT_COUNT="$OPTARG";;
		b) OP_BITRATES="$OPTARG";;
		f) NO_FORK=1;;
		p) PLAYLIST_PREFIX="$OPTARG";;
		t) SEGMENT_PREFIX="$OPTARG";;
		S) SEGMENT_DIRECTORY="$OPTARG";;
		e) ENCRYPT=1;;
        esac
done


if [ "$LEGACY_ARGS" == "1" ]
then
  # Old Basic Usage is 
  # cmd.sh inputfile segmentlength 

  INPUTFILE=${INPUTFILE:-$1}
  SEGLENGTH=${SEGLENGTH:-$2}
  if ! [ -z "$3" ]
  then
    OUTPUT_DIRECTORY=$3
  fi
fi

input_file_checker "${INPUTFILE}"

# Check we've got the arguments we need
if [ "$INPUTFILE" == "" ] || [ "$SEGLENGTH" == "" ]
then
  print_usage
fi

# FFMpeg is a pre-requisite, so let check for it
if hash $FFMPEG 2> /dev/null
then
  # FFMpeg exists
  echo "ffmpeg command found.... continuing"
else
  # FFMPeg doesn't exist, uh-oh!
  echo "Error: FFmpeg doesn't appear to exist in your PATH. Please addresss and try again"
  exit 1
fi

# Check whether the input is a named pipe
if [ -p "$INPUTFILE" ]
then
  echo "Warning: Input is FIFO - EXPERIMENTAL"
  IS_FIFO=1

fi

# Check output directory exists otherwise create it
if [ ! -w $OUTPUT_DIRECTORY ]
then
  echo "Creating $OUTPUT_DIRECTORY"
  mkdir -p $OUTPUT_DIRECTORY
fi

if [ "$LIVE_STREAM" == "1" ]
then
    FFMPEG_ADDITIONAL+="-segment_list_flags +live"

    if [ "$LIVE_SEGMENT_COUNT" -gt 0 ]
    then
	WRAP_POINT=$(($LIVE_SEGMENT_COUNT * 2)) # Wrap the segment numbering after 2 manifest lengths - prevents disks from filling
	FFMPEG_ADDITIONAL+=" -segment_list_size $LIVE_SEGMENT_COUNT -segment_wrap $WRAP_POINT"
    fi
fi


# Pulls file name from INPUTFILE which may be an absolute or relative path.
INPUTFILENAME=${INPUTFILE##*/}

# If a prefix hasn't been specified, use the input filename
PLAYLIST_PREFIX=${PLAYLIST_PREFIX:-$INPUTFILENAME}
SEGMENT_PREFIX=${SEGMENT_PREFIX:-$PLAYLIST_PREFIX}

# The 'S' option allows segments and bitrate specific manifests to be placed in a subdir
SEGMENT_DIRECTORY=${SEGMENT_DIRECTORY:-''}

# TLM Name
if [ "$VIDEO_ONLY" == "1" ]
then
    TLM_PREFIX="_No_Audio"$TLM_PREFIX
fi

if [ ! "$SEGMENT_DIRECTORY" == "" ]
then

	if [ ! -d "${OUTPUT_DIRECTORY}/${SEGMENT_DIRECTORY}" ]
	then
		mkdir -p "${OUTPUT_DIRECTORY}/${SEGMENT_DIRECTORY}"
	fi

        OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY}/${SEGMENT_DIRECTORY}"

	SEGMENT_DIRECTORY+="/"
fi

# Set the bitrate
if [ ! "$OP_BITRATES" == "" ]
then
      # Make the bitrate list easier to parse
      OP_BITRATES=${OP_BITRATES//,/$'\n'}

      # Create an array to house the pids for backgrounded tasks
      declare -a PIDS
      declare -a BITRATE_PROCESSES

      mkdir -p "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}"

      # Get the variant playlist created
      createVariantPlaylist "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}"
      for br in $OP_BITRATES
      do
	    appendVariantPlaylistentry "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}${TLM_PREFIX}" "${PLAYLIST_PREFIX}/${br}/${PLAYLIST_PREFIX}_${br}.m3u8" "$br"
      done

      # Now for the longer running bit, transcode the video
      for br in $OP_BITRATES
      do
          #Accept bitrates as given
	      BITRATE="-b:v ${br}"
	      # Finally, lets build the output filename format
	      OUT_NAME="${SEGMENT_PREFIX}_${br}_%05d.ts"

              mkdir -p "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}/${br}"

	      PLAYLIST_NAME="$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}/${br}/${PLAYLIST_PREFIX}_${br}.m3u8"
	      SOURCE_FILE="$INPUTFILE"
	      echo "Generating HLS segments for bitrate ${br}k - this may take some time"

	      if [ "$NO_FORK" == "0" ] || [ "$LIVE_STREAM" == "1" ]
	      then
		      # Processing Starts
		      if [ "$IS_FIFO" == "1" ]
		      then
			    # Create a FIFO specially for this bitrate
			    SOURCE_FILE="$TMPDIR/hlsc.encode.$MYPID.$br"
			    mknod "$SOURCE_FILE" p
		      fi

		      # Schedule the encode
		      createStream "$PLAYLIST_NAME" "$OUT_NAME" "$BITRATE" "$SOURCE_FILE" &
		      PID=$!
		      PIDS=(${PIDS[@]} $PID)
  		      BITRATE_PROCESSES=("${BITRATE_PROCESSES[@]}" ${br})
	      else
		      createStream "$PLAYLIST_NAME" "$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}/${br}/$OUT_NAME" "$BITRATE" "$SOURCE_FILE"

                      addstreamtype "$PLAYLIST_NAME" "$LIVE_STREAM"
	      fi
      done

      if [ "$IS_FIFO" == "1" ]
      then
	      # If the input was a FIFO we need to read from it and push into the new FIFOs
	      cat "$INPUTFILE" | tee $(for br in $OP_BITRATES; do echo "$TMPDIR/hlsc.encode.$MYPID.$br"; done) > /dev/null &
	      TEE_PID=$!
      fi

      if [ "$NO_FORK" == "0" ] || [ "$LIVE_STREAM" == "1" ]
      then
	    # Monitor the background tasks for completion
	    echo "All transcoding processes started, awaiting completion"
	    awaitCompletion
      fi

      if [ "$IS_FIFO" == "1" ]
      then
	    for br in $OP_BITRATES
	    do 
		rm -f "$TMPDIR/hlsc.encode.$MYPID.$br"; 
	    done
	    # If we were interrupted, tee may still be running
	    kill $TEE_PID 2> /dev/null 
      fi

      if [ "$VIDEO_ONLY" == "0" ]
      then
         # Encode all the Audio Stream as Alternates
         a_streams=""
         for br_playlist in `cat ${OUTPUT_DIRECTORY}/${PLAYLIST_PREFIX}${TLM_PREFIX} | awk '/#EXT-X-STREAM-INF:.*BANDWIDTH=/{getline;print}'`
         do
             for seg in `cat ${OUTPUT_DIRECTORY}/$br_playlist | awk '/#EXTINF:/{getline;print}'` 
             do
                 audio_stream=`ffprobe  -v quiet -i ${OUTPUT_DIRECTORY}/$(dirname "$br_playlist")/$seg -show_streams -select_streams a`
                 for j in `echo $audio_stream | awk '{ split($0, list, " "); for (i in list) print list[i]  }'`;
                 do
                     if [[ $j == *"codec_name="* ]]; 
                     then
                         a_streams+="${j##*=}:"
                     fi;
                     if [[ $j == *"language="* ]];
                     then
                         a_streams+="${j##*=},"
                     fi
                 done
         
                 if [ ! "$a_streams" == "" ]
                 then
                     break
                 fi
             done
         
             if [ ! "$a_streams" == "" ]
             then
                 break
             fi
         done

         for au in `echo $a_streams | awk '{ split($0, str, ","); for (i in str) print str[i] }' `;
         do
             createAudioEntry ${OUTPUT_DIRECTORY}/$br_playlist ${au%:*} ${au##*:} 
             appendAudioAttrForVideoPlayListEntry ${au%:*}
         done
      fi
else

  OUTPUT_DIRECTORY+=$SEGMENT_DIRECTORY
  # No bitrate specified

  # Finally, lets build the output filename format
  OUT_NAME="${SEGMENT_PREFIX}_%05d.ts"
  PLAYLIST_NAME="$OUTPUT_DIRECTORY/${PLAYLIST_PREFIX}.m3u8"

  echo "Generating HLS segments - this may take some time"

  # Processing Starts

  createStream "$PLAYLIST_NAME" "$OUT_NAME" "$BITRATE" "$INPUTFILE"

  addstreamtype "$PLAYLIST_NAME" "$LIVE_STREAM"

  if [ "$ENCRYPT" == "1" ] && [ "$LIVE_STREAM" == "0" ]
  then
    encrypt
  fi
fi

if [ "$URL_INPUT_FILE" == "1" ]
then
   rm -f $INPUTFILE
fi

