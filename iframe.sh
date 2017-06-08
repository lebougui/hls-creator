#!/bin/bash
#################################################################################
#
# AUTHOR            : Lebougui
# DATE              : 2016/03/14
# DESCRIPTION       : Iframe generator
#
#################################################################################
VERSION="1.0"
MAINTAINERS="Lebougui"
TRUE="true"
FALSE="false"
DATE="2016/03/14"  

VERBOSE=$FALSE

#set -x

# display this script help
help() {
cat << EOF
Usage : $0 -h -l <master playlist location> -t <iframe type >

Retrieve all playlists file from a folder and generate the two iframes playlists :
- byte range based ones
- transport streams based ones.

OPTIONS :
        -h              displays this help
        -l              master playlist location
        -t              byterange or default

        Examples : 
        $0 -l /cdn/video_TLM.m3u8 -t default (Not complete yet)
        $0 -l /cdn/video_TLM.m3u8 -t byterange

EOF

version

}

# display this script version
version() {
    echo -e "Version       : $0 $VERSION ($DATE) " 
    echo -e "Maintainer(s) : $MAINTAINERS \n"
}


validate_params() {
    if [ -z "$2" ] 
    then
        echo -e "Bad $1 (given is $2)."
        help
        exit -1
    fi
}

set_platform_name()
{
    case `uname -s` in
        Linux) PLATFORM="Linux"
        ;;

        Darwin)PLATFORM="Mac-OS"
        ;;

        *)echo "Unknown platoform".
          exit 1
    esac
}

add_iframe_playlist_into_tlm()
{
    tlm_m3u8=$1
    playlist_basename_suffix=$2

    sed -i.bak 's|#EXT-X-I-FRAME-STREAM-INF.*||g' "$tlm_m3u8" && rm -f "$tlm_m3u8.bak"

	declare -a bandwidth_list
	bandwidth_list=($(cat $tlm_m3u8 | awk 'BEGIN{FS=":"}{if(match($0,"#EXT-X-STREAM-INF")){sub(".*BANDWIDTH=", ""); sub(",.*", "");print $0}}'))

	for entry in $(echo ${bandwidth_list[@]})
	do
        line=$(cat $tlm_m3u8 | grep -n $entry | cut -d":" -f1)
        media_playlist=$(cat $tlm_m3u8 | sed -n ''$(($line+1))'p')
        ts_folder="$(dirname $media_playlist)"        
        iframe_playlist_name="$(basename $media_playlist '.m3u8')_$playlist_basename_suffix.m3u8"
		echo "#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=$entry,URI=\"$ts_folder/$iframe_playlist_name\"" >> $tlm_m3u8
	done

    sed -i.bak '/^$/d' "$tlm_m3u8" && rm -f "$tlm_m3u8.bak"

	unset bandwidth_list
}

PLATFORM=""
IFRAME_TYPE="default"

while getopts "hl:t:" param; do

   case $param in
       h) help
          exit 0
       ;;

       l)LOCATION="$OPTARG"
       ;;

       t)IFRAME_TYPE="$OPTARG"
       ;;

       *) echo "Invalid option"
          help
          exit 1
       ;;
   esac

done

shift $(($OPTIND -1 ))

validate_params "Top level (master) playlist location" $LOCATION

set_platform_name
if [ "$PLATFORM" == "Linux" ]
then
    SORT="sort"
else
    SORT="sort"
fi

tmp_file=$(mktemp)
case $IFRAME_TYPE in  
    "byterange")
		#type 2 = byte range
		for tlm_m3u8 in $(find $LOCATION -maxdepth 1 -type f -name "*.m3u8")
		do  
         	declare -a media_playlist

			media_playlist=($(cat $tlm_m3u8 | awk '{if (substr($0,1,1) != "#"){ print $0;}}'))
			media_playlist_index=$(echo ${media_playlist[@]} | awk '{print NF}')

			entry_index=0
			while [ $entry_index -lt $media_playlist_index ]
			do
				ts_folder="$(dirname "$LOCATION")/$(dirname ${media_playlist[$entry_index]})"
				cd $ts_folder
				iframe_playlist_name="$(basename ${media_playlist[$entry_index]} .m3u8)_byterange_iframe.m3u8"
				rm -rf `find . -type f -name "*iframe*"`

	   			echo "#EXTM3U" > $iframe_playlist_name
				echo "#EXT-X-TARGETDURATION:" >> $iframe_playlist_name
				echo "#EXT-X-VERSION:4" >> $iframe_playlist_name
				echo "#EXT-X-MEDIA-SEQUENCE:0" >> $iframe_playlist_name
                		echo "#EXT-X-PLAYLIST-TYPE:VOD" >> $iframe_playlist_name
            			echo "#EXT-X-I-FRAMES-ONLY" >> $iframe_playlist_name

				SEGMENTED_FILES=$(find . -name "*.ts" | $SORT -n)
				target_duration="0"

				for ts in ${SEGMENTED_FILES}
				do
                    			declare -a IFRAMES_DATA
					declare -a IFRAMES_BEST_EFFORT_TIME
					declare -a IFRAMES_PKT_SIZE
					declare -a IFRAMES_PKT_POS
					declare -a VIDEO_PACKETS_POS
                    			declare -a IFRAMES_DATA

				    	ALL_PACKETS=$(ffprobe -v quiet -show_packets  -show_frames $ts -of compact > $tmp_file)
				    	VIDEO_PACKETS_POS=($(grep 'packet' $tmp_file | grep 'codec_type=video' | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pos")){split($i, tab, "="); print tab[2];}} }'))

					IFRAMES_DATA=($(grep 'pict_type=I' $tmp_file | grep 'key_frame=1'))
	                		if [ ${#IFRAMES_DATA[@]} -eq 0 ]
                    			then
                        			continue
                    			fi
					IFRAMES_BEST_EFFORT_TIME=($(echo ${IFRAMES_DATA[@]}  | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"best_effort_timestamp_time")){split($i, tab, "="); print tab[2];}} }'))
					IFRAMES_PKT_SIZE=($(echo ${IFRAMES_DATA[@]} | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pkt_size")){split($i, tab, "="); print tab[2];}} }'))
					IFRAMES_PKT_POS=($(echo ${IFRAMES_DATA[@]} | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pkt_pos")){split($i, tab, "="); print tab[2];}} }'))         

					GET_LAST_BEST_EFFORT_TIME=$(tail -1 $tmp_file | sed -n "s/.*best_effort_timestamp_time=\([0-9]*.[0-9]*\).*/\1/p")

					i=0
					while [ $i -le "$((${#IFRAMES_DATA[@]} - 1))" ]
					do
						RESULT=""
						next_index="$(($i+1))"
						if [ $i -lt "$((${#IFRAMES_DATA[@]} - 1))" ]
						then
						  RESULT=$(echo "${IFRAMES_BEST_EFFORT_TIME[$next_index]} - ${IFRAMES_BEST_EFFORT_TIME[$i]}" | bc -l | awk '{printf "%f", $0}')
						else
						  RESULT=$(echo "$GET_LAST_BEST_EFFORT_TIME - ${IFRAMES_BEST_EFFORT_TIME[$i]}" | bc -l | awk '{printf "%f", $0}')
						fi

				        	if [ $(echo "($RESULT - $target_duration) > 0" | bc -l) -gt 0 ]
				        	then
				            	target_duration=$RESULT
				        	fi
				        	echo "#EXTINF:${RESULT}," >> $iframe_playlist_name
				        	j=0
				        	size=${IFRAMES_PKT_SIZE[$i]}
				        	while [ $j -le "$((${#VIDEO_PACKETS_POS[@]}-1))" ]
				        	do
				            		if [ $(echo "(${VIDEO_PACKETS_POS[$j]} - ${IFRAMES_PKT_POS[$i]})" | bc -l) -eq 0 ]
				            		then
				                	if [ ! -z ${VIDEO_PACKETS_POS[$(($j+1))]} ]
				                	then
				                    		size=$(echo "((${VIDEO_PACKETS_POS[$(($j+1))]} - ${VIDEO_PACKETS_POS[$j]}) + 188)" | bc -l)
				                    		break
                                			fi
				            		fi
							j=$(($j+1))
				        	done
				        	echo "#EXT-X-BYTERANGE:$size@${IFRAMES_PKT_POS[$i]}" >> $iframe_playlist_name

						echo "$ts" >> $iframe_playlist_name
						i=$(($i+1))
					done
					unset IFRAMES_BEST_EFFORT_TIME
					unset IFRAMES_PKT_SIZE
					unset IFRAMES_PKT_POS
					unset VIDEO_PACKETS_POS
                    			unset IFRAMES_DATA
				done
				echo "#EXT-X-ENDLIST" >> $iframe_playlist_name

                target_duration=$(echo $target_duration | awk 'function ceil(valor){return (valor == int(valor)) ? valor : int(valor)+1}{printf "%d", ceil($0)}')
                sed -i.bak 's|#EXT-X-TARGETDURATION:.*|#EXT-X-TARGETDURATION:'$target_duration'|g' "$iframe_playlist_name" && rm -f "$iframe_playlist_name.bak"

				cd - 
				entry_index=$(($entry_index+1))
			done

            add_iframe_playlist_into_tlm $tlm_m3u8 "byterange_iframe"

			unset media_playlist

		done
    ;;

    "default"|*)
    #type 1 = iframe ts
	for tlm_m3u8 in $(find $LOCATION -maxdepth 1 -type f -name "*.m3u8")
	do  
		declare -a media_playlist

		media_playlist=($(cat $tlm_m3u8 | awk '{if (substr($0,1,1) != "#"){ print $0;}}'))
		bandwidth_list=($(cat $tlm_m3u8 | awk 'BEGIN{FS=":"}{if(match($0,"#EXT-X-STREAM-INF")){sub(".*BANDWIDTH=", ""); sub(",.*", "");print $0}}'))

		entry_index=0
		while [ $entry_index -le $((${#media_playlist[@]} - 1)) ]
		do
            ts_folder="$LOCATION/$(dirname ${media_playlist[$entry_index]})"   
		    iframe_playlist_name="$ts_folder/$(basename ${media_playlist[$entry_index]} .m3u8)_iframe.m3u8"

		    rm -rf $(find $ts_folder -type f -name "*iframe*")

			for ts in $(find $ts_folder -type f -name "*.ts" | $SORT -V)
			do
				prefix_iframe=$(basename $ts ".ts")
				
                ffmpeg -y -i "$ts" \
                          -vf "select='eq(pict_type\,PICT_TYPE_I)'" \
						  "$ts_folder/"$prefix_iframe"_iframe.ts"

			done

            echo "#EXTM3U" > $iframe_playlist_name
			echo "#EXT-X-TARGETDURATION:" >> $iframe_playlist_name
			echo "#EXT-X-VERSION:4" >> $iframe_playlist_name
            echo "#EXT-X-PLAYLIST-TYPE:VOD" >> $iframe_playlist_name
			echo "#EXT-X-MEDIA-SEQUENCE:0" >> $iframe_playlist_name
            echo "#EXT-X-I-FRAMES-ONLY" >> $iframe_playlist_name

			target_duration=0
			for iframe in $(find $ts_folder -type f -name "*iframe.ts" | $SORT -V)
			do
		        declare -a IFRAMES_DATA
				declare -a IFRAMES_BEST_EFFORT_TIME
				declare -a IFRAMES_PKT_SIZE
				declare -a IFRAMES_PKT_POS
				declare -a VIDEO_PACKETS_POS
		        declare -a IFRAMES_DATA

		        ALL_PACKETS=$(ffprobe -v quiet -show_packets  -show_frames $iframe -of compact > $tmp_file)
				VIDEO_PACKETS_POS=($(grep 'packet' $tmp_file | grep 'codec_type=video' | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pos")){split($i, tab, "="); print tab[2];}} }'))

				IFRAMES_DATA=($(grep 'pict_type=I' $tmp_file | grep 'key_frame=1'))
		        if [ ${#IFRAMES_DATA[@]} -eq 0 ]
		        then
		            continue
		        fi
				IFRAMES_BEST_EFFORT_TIME=($(echo ${IFRAMES_DATA[@]}  | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"best_effort_timestamp_time")){split($i, tab, "="); print tab[2];}} }'))
				IFRAMES_PKT_SIZE=($(echo ${IFRAMES_DATA[@]} | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pkt_size")){split($i, tab, "="); print tab[2];}} }'))
				IFRAMES_PKT_POS=($(echo ${IFRAMES_DATA[@]} | awk 'BEGIN{FS="|"} {for(i=1; i<=NF; i++){if(match($i,"pkt_pos")){split($i, tab, "="); print tab[2];}} }'))         

				GET_LAST_BEST_EFFORT_TIME=$(tail -1 $tmp_file | sed -n "s/.*best_effort_timestamp_time=\([0-9]*.[0-9]*\).*/\1/p")

				i=0
			    duration=0
				while [ $i -le "$((${#IFRAMES_DATA[@]} - 1))" ]
				do
					next_index="$(($i+1))"
					if [ $i -lt "$((${#IFRAMES_DATA[@]} - 1))" ]
					then
					  duration=$(echo "$duration + (${IFRAMES_BEST_EFFORT_TIME[$next_index]} - ${IFRAMES_BEST_EFFORT_TIME[$i]})" | bc -l)
					else
					  duration=$(echo "$duration + ($GET_LAST_BEST_EFFORT_TIME - ${IFRAMES_BEST_EFFORT_TIME[$i]})" | bc -l)
					fi

				    if [ $(echo "($duration - $target_duration) > 0" | bc -l) -gt 0 ]
				    then
				        target_duration=$duration
				    fi
					i=$(($i+1))
				done
                
                echo "#EXTINF:$duration" >> $iframe_playlist_name
				echo "$(basename $iframe)" >> $iframe_playlist_name

				unset IFRAMES_BEST_EFFORT_TIME
				unset IFRAMES_PKT_SIZE
				unset IFRAMES_PKT_POS
				unset VIDEO_PACKETS_POS
		        unset IFRAMES_DATA
			done

            target_duration=$(echo $target_duration | awk 'function ceil(valor){return (valor == int(valor)) ? valor : int(valor)+1}{printf "%d", ceil($0)}')
            sed -i.bak 's|#EXT-X-TARGETDURATION:.*|#EXT-X-TARGETDURATION:'$target_duration'|g' "$iframe_playlist_name" && rm -f "$iframe_playlist_name.bak"

			echo "#EXT-X-ENDLIST" >> $iframe_playlist_name

            entry_index=$(($entry_index+1))
        done

        add_iframe_playlist_into_tlm $tlm_m3u8 "iframe"

		unset media_playlist

	done
    ;;
esac
rm -rf $tmp_file




