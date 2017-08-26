#!/bin/bash
#
# Plex post processing script
#
# preset info
# http://dev.beandog.org/x264_preset_reference.html
# https://trac.ffmpeg.org/wiki/Encode/H.264
# http://www.chaneru.com/Roku/HLS/X264_Settings.htm
#
# Frame Rates
#
# 60000	1001	59.94005994	720p broadcast (-r 60000/1001)
# 30000	1001	29.97002997	1080i broadcast (-r ntsc)
# 30000	1001	29.97002997	480i broadcast (-r 30000/1001)
# 24000	1001	23.97602398	film (-r 24000/1001)
#
# -pix_fmt yuv420p or -vf format=yuv420p
#

# adjust per need
ffprobe="/volume1/@appstore/ChannelsDVR/channels-dvr/latest/ffprobe"
ffmpeg="/var/packages/EmbyServer/target/ffmpeg/bin/ffmpeg_real"
# plex tickets location
plex_tickets="/var/tmp/plex_tickets.txt"
job_id=$$
job_wait_timer=5
# job monitoring
results_file="/var/tmp/plex-results-${job_id}.txt"
# encode time, only modify this to test things.
# example below is only encode video for 5 seconds
#time="-t 5"
time=""
#frame_rate="-r 24000/1001"
# leave frame rate unmodified (except for 720p currently)
frame_rate=""
# downgrade 1080i to 720p
downgrade_1080i="true"
# downgrade 720p from 60fps to 30fps and level to 3.1
downgrade_720p="true"

>$results_file
echo "$@" >>$results_file

echo "$1" >> /var/tmp/plex_post_processing_files.txt
output="$(echo "$1" | sed "s#\.mpg\$#\.mp4#" | sed "s#\.ts\$#\.mp4#" | sed "s#\.mkv\$#\.mp4#")"
filename="$(basename "$1")"

video=$($ffprobe -hide_banner -i "$1" 2>&1 | egrep " Video: ")
format=$(echo $video | sed 's#.* \([[:digit:]]\+x[[:digit:]]\+ [SAR [[:digit:]]\+:[[:digit:]]\+ DAR [[:digit:]]\+:[[:digit:]]\+]\).*#\1#')
height=$(echo $format | sed "s#[[:digit:]]\+x\([[:digit:]]\+\) .*#\1#")

# /var/packages/EmbyServer/target/ffmpeg/bin/ffmpeg_real -h encoder=libx264
# some options to transform preset to even faster
# not yet added to encode lines, this is the preset additional overrides from emby
encode_opts="-x264opts:0 subme=0:me_range=4:rc_lookahead=10:me=dia:no_chroma_me:8x8dct=0:partitions=none"
#encode_opts=""

# 4:3 SD AR's
crop_list="
352x480 [SAR 20:11 DAR 4:3]
528x480 [SAR 40:33 DAR 4:3]
544x480 [SAR 20:17 DAR 4:3]
704x480 [SAR 10:11 DAR 4:3]
720x480 [SAR 8:9 DAR 4:3]
"

# 16:9 SD AR's
list_widescreen="
528x480 [SAR 160:99 DAR 16:9]
704x480 [SAR 40:33 DAR 16:9]
720x480 [SAR 32:27 DAR 16:9]
"

# routine to queue jobs
queue_job () { 
	echo "Queueing job: $job_id" >>$results_file

	if [ ! -f "${plex_tickets}" ] ; then
		echo $job_id >>"${plex_tickets}"
		#set initial mode of file
		chmod 666 "${plex_tickets}" >>$results_file 2>&1
	else
		echo $job_id >>"${plex_tickets}"
	fi

	current_job=$(head -1 "${plex_tickets}")

	while [ $job_id -ne $current_job ] ; do
		depth=0
		echo "Job: ${job_id} is not ready.  Job: ${current_job} is running" >>$results_file

		while IFS= read -r ; do
			ticket=$REPLY
			let depth++
			if [ ${job_id} -eq ${ticket} ] ; then
				position=${depth}
				#break
			fi
		done < "${plex_tickets}"
		#depth=$(wc -l $plex_tickets | awk '{print $1}')

		echo "Job: ${job_id} queue position ${position} of ${depth}." >>$results_file
		echo "Sleeping ${job_wait_timer} seconds" >>$results_file
		sleep ${job_wait_timer}
		current_job=$(head -1 "${plex_tickets}")
	done

	echo "Job: ${job_id} is ready!" >>$results_file
}

# routine to remove jobs
remove_job () {
	echo "Removing job: ${job_id} from ${plex_tickets}" >>$results_file

	# this step actually creates a new file with new ownerships, but maintains previous mode
	sed -i "/^$job_id$/d" "${plex_tickets}"
}

transcode_dvr="false"
# check formats to transcode
OLDIFS=$IFS
IFS=$'\n'
for value in $crop_list ; do
	if [ "$value" = "$format" ] ; then
		transcode_dvr="true"
		break
	fi
done
IFS=$OLDIFS

# encode 480i 4:3 material
if [ "$transcode_dvr" = "true" ] ; then
	#frame_rate=""
	#frame_rate="-r 24000/1001"
	# scale everything to 480p
	#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=720:480"
	# scale everything to widescreen 640:480
	#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:480"
	# probably makes most sense to use this scale, all these sources are scaled to 640 width anyhow due to sar settings.
	# this would give a 1:1 sar and a smaller file
	filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:360"
	# fancy way to calculate 360
	#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:ceil((out_w/dar/2)*2)"
	#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120"
	#size="-s 720x480"
	size=""
	#audio_codec="copy"
	audio_codec="aac -ac 2 -ab 192000"
	#audio_codec="aac -ac 2 -ab 192k"
	#audio_codec="aac -strict experimental -ac 2 -ab 384000"
	#audio_codec="aac -strict experimental -ac 2 -ab 192000"
	movflags="-movflags faststart"
	#aspect="-aspect 16:9"
	aspect=""
	crf=17
	#preset="medium"
	preset="veryfast"
	# 720x480 30fps
	level="3.0"

	# These shows play letterboxed 16:9 when they are actually 4:3
	shows="Charmed|Married"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		# this is filter line if using 640:480 or 720:480 frames
		#filter="$filter -aspect 4:3"
		# use this filter if using the above 1:1 sar 640x360
		filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:480 -aspect 4:3"
	fi

	# These shows do not need cropping and are 4:3
	# Will & Grace plays on WEtv in 4:3
	# not all episodes of SpongeBob play in 4:3 :(
	shows="SpongeBob|Will & Grace"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		# scale to 480p
		#filter="-vf yadif=0:-1:0,scale=720:480"
		# scale to 640:480
		filter="-vf yadif=0:-1:0,scale=640:480"
	fi

	queue_job
	$ffmpeg -hide_banner -i "$1" -vcodec libx264 -preset ${preset} -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
	rm "$1"
	remove_job
fi

transcode_dvr="false"
# check formats to transcode
OLDIFS=$IFS
IFS=$'\n'
for value in $list_widescreen ; do
	if [ "$value" = "$format" ] ; then
		transcode_dvr="true"
		break
	fi
done
IFS=$OLDIFS

# encode 480i 16:9 material
if [ "$transcode_dvr" = "true" ] ; then
	#frame_rate=""
	#frame_rate="-r 24000/1001"
	size=""
	filter="-vf yadif=0:-1:0,scale=720:480"
	audio_codec="aac -ac 2 -ab 192000"
	movflags="-movflags faststart"
	aspect=""
	crf=17
	preset="veryfast"
	# 720x480 30fps
	level="3.0"

	queue_job
	$ffmpeg -hide_banner -i "$1" -vcodec libx264 -preset ${preset} -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
	rm "$1"
	remove_job
fi

# encode 1080i material
if [ $height -eq 1080 ] ; then
	#frame_rate=""
	#frame_rate="-r 24000/1001"
	size=""
	audio_codec="aac -ac 2 -ab 192000"
	movflags="-movflags faststart"
	aspect=""
	crf=17
	preset="veryfast"

	if [ "$downgrade_1080i" = "true" ] ; then
		# deinterlace and reduce to 720
		filter="-vf yadif=0:-1:0,scale=1280:720"
		# 960:540 idea
		#filter="-vf yadif=0:-1:0,scale=iw/2:-1"
		# may need to issue this, but it should already be at 30fps if it was 1080i
		#frame_rate="-r 30000/1001"
		# 1280x720 30fps
		level="3.1"
		# 1280x720 60fps
		#level="3.2"
	else
		# convert to 1080p via deinterlace
		filter="-vf yadif=0:-1:0"
		# 1920x1080 30fps
		# Samsung - Galaxy Tab A needs level 4.0
		level="4.0"
		# 1920x1080 30fps (higher bitrates)
		#level="4.1"
	fi

	queue_job
	$ffmpeg -hide_banner -i "$1" -vcodec libx264 -preset ${preset} -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
	rm "$1"
	remove_job
fi

# encode 720p material
if [ $height -eq 720 ] ; then
	#frame_rate=""
	#frame_rate="-r 24000/1001"
	size=""
	filter=""
	audio_codec="aac -ac 2 -ab 192000"
	movflags="-movflags faststart"
	aspect=""
	crf=17
	preset="veryfast"

	if [ "$downgrade_720p" = "true" ] ; then
		#reduce frame rate from 60fps to 30fps
		frame_rate="-r 30000/1001"
		# 1280x720 30fps
		level="3.1"
	else
		#this value should already be set in stream
		#frame_rate="-r 60000/1001"
		# 1280x720 60fps
		level="3.2"
	fi

	# Friends is broadcasted interlaced in 720p on WMYD
	shows="Friends"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		filter="-vf yadif=0:-1:0"
	fi

	#if echo $video | grep progressive >/dev/null 2>&1 ; then
		#filter=""
	#else
		#filter="-vf yadif=0:-1:0"
	#fi

	queue_job
	$ffmpeg -hide_banner -i "$1" -vcodec libx264 -preset ${preset} -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
	rm "$1"
	remove_job
fi
