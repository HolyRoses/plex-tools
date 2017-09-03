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
#
# path where plex stores its external decoding and encoding libraries, not sure why they are using external libs
# by default the permissions in this path are not readable unless you are plex user
FFMPEG_EXTERNAL_LIBS="/volume1/Plex/Library/Application Support/Plex Media Server/Codecs/798f007-1247-linux-synology-i686/" ; export FFMPEG_EXTERNAL_LIBS
# have to set this because their ffmpeg isn't statically linked.
LD_LIBRARY_PATH="/volume1/@appstore/Plex Media Server/" ; export LD_LIBRARY_PATH
# renamed ffmpeg
ffmpeg="/volume1/@appstore/Plex Media Server/Plex Transcoder"
ffprobe="$ffmpeg"
# original ffmpeg/ffprobe I was using
#ffprobe="/volume1/@appstore/ChannelsDVR/channels-dvr/latest/ffprobe"
#ffmpeg="/var/packages/EmbyServer/target/ffmpeg/bin/ffmpeg_real"
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
# may want to look at using bash substring replacment
# http://www.tldp.org/LDP/abs/html/string-manipulation.html
#output=${1//.ts/.mp4}
output="$(echo "$1" | sed "s#\.mpg\$#\.mp4#" | sed "s#\.ts\$#\.mp4#" | sed "s#\.mkv\$#\.mp4#")"
filename="$(basename "$1")"

video=$("$ffprobe" -hide_banner -i "$1" 2>&1 | egrep " Video: ")
format=$(echo $video | sed 's#.* \([[:digit:]]\+x[[:digit:]]\+ [SAR [[:digit:]]\+:[[:digit:]]\+ DAR [[:digit:]]\+:[[:digit:]]\+]\).*#\1#')
height=$(echo $format | sed "s#[[:digit:]]\+x\([[:digit:]]\+\) .*#\1#")

# /var/packages/EmbyServer/target/ffmpeg/bin/ffmpeg_real -h encoder=libx264
# some options to transform preset to even faster
# not yet added to encode lines, this is the preset additional overrides provided from Plex or Emby
#https://support.plex.tv/hc/en-us/articles/200250347-Transcoder
#Prefer higher speed encoding:
#encode_opts="-x264opts subme=0:me_range=4:rc_lookahead=10:me=dia:no_chroma_me:8x8dct=0:partitions=none"
#Prefer higher quality encoding:
#encode_opts="-x264opts subme=0:me_range=4:rc_lookahead=10:me=hex:8x8dct=0:partitions=none"
#Make my CPU hurt:
#encode_opts="-x264opts subme=2:me_range=4:rc_lookahead=10:me=hex:8x8dct=1"
encode_opts=""

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
	#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:360"
	# new filter
	filter="-vf yadif=0:-1:0,crop=in_w:in_h/dar,scale=ih*16/9:ih"
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

	# These shows play letterboxed 16:9 when they are actually 4:3 (no pillar box, when it should be pillar boxed)
	# Family Guy on TOON (Adult Swim) plays stretched 16:9, its a 4:3 show
	# Charmed on TNT plays stretched 16:9, its a 4:3 show
	# Married ... With Children on TBS plays stretched 16:9, its a 4:3 show
	shows="Charmed|Married|Family Guy"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		# this is filter line if using 640:480 or 720:480 frames (from above)
		#filter="$filter -aspect 4:3"
		# use this filter if using the above 1:1 sar 640x360
		# this should probably be 480x360 as we are cropping to 360 height, snapping it inwards would make it 480, need run a test against material
		# better yet, re-write this to not use digits, to make more universal
		# original filter
		#filter="-vf yadif=0:-1:0,crop=in_w:in_h-120,scale=640:480 -aspect 4:3"
		# rewrite, should scale to 480x360 if provided a 640:480 frame and also do an aspect ratio correction, otherwise we would have a 16:9 image inside that 4:3 box
		# if provided a 1440x1080 image it would generate a 1080x810 image, a 960x720 image would generate a 720x540 output
		# if ran against non wide stretched material, then this will shrink things inward and people will look squished
		#filter="-vf yadif=0:-1:0,crop=in_w:in_h/dar,scale=iw/(4/3):ih -aspect 4:3"
		filter="-vf yadif=0:-1:0,crop=in_w:in_h/dar,scale=ih*4/3:ih -aspect 4:3"
	fi

	# This crops a 4:3 picture out of a 16:9 pillar boxed frame (which is also encased in a 4:3 frame)
	# Filter below is to crop a 4:3 frame, that is encased inside a 16:9 frame, which is encased inside a 4:3 frame.
	# Basic formula is actually quite simple, example:  =528-480/40*33 = 132 crop value
	# This will take any non square pixel 4:3 source and crop out the 480x360 square inside
	# Outlaw Star (1998) needs this filter
	# This is the most advanced filter in script, others probably should be remodeled to work more like this, especially the scaling.
	shows="Outlaw Star"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		filter="-vf yadif=0:-1:0,crop=in_h/sar:in_h/dar,scale=iw*sar:ih"
	fi

	# These shows do not need cropping and are 4:3
	# Will & Grace plays on WEtv in 4:3
	# not all episodes of SpongeBob play in 4:3 :(
	shows="SpongeBob|Will & Grace"
	if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
		# scale to 480p
		#filter="-vf yadif=0:-1:0,scale=720:480"
		# scale to 640:480
		#filter="-vf yadif=0:-1:0,scale=640:480"
		#this scale is not always safe, if input was 16:9 and 480 height, then it would produce 853 width, which would fail.
		#in this case though we know the input is always going to be 480 and a width of 640
		filter="-vf yadif=0:-1:0,scale=ih*dar:ih"
	fi

	queue_job
	"$ffmpeg" -hide_banner -i "$1" -vcodec libx264 -preset ${preset} $encode_opts -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
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
	"$ffmpeg" -hide_banner -i "$1" -vcodec libx264 -preset ${preset} $encode_opts -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
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

	# 4:3 shows broadcasted pillar boxed in 16:9
	# Season 13 of King of the Hill was broadcast in 16:9, so may want to improve this regex
	# Reason for cropping these 16:9 signals is so that on non 16:9 screens they will zoom or play properly.  Otherwise will play in center of screen.
	# King of the Hill plays on WADL, Family Guy plays on CW50, On Fox Family Guy plays in 16:9
	shows="King of the Hill|Family Guy"

	if [ "$downgrade_1080i" = "true" ] ; then
		if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
			# crop and scale to 4:3 720p (960x720)
			filter="-vf yadif=0:-1:0,crop=in_h*(4/3):in_h,scale=oh*(4/3):720"
		else
			# deinterlace and reduce to 720p
			filter="-vf yadif=0:-1:0,scale=1280:720"
		fi
		# 960:540 idea
		#filter="-vf yadif=0:-1:0,scale=iw/2:-1"
		# may need to issue this, but it should already be at 30fps if it was 1080i
		#frame_rate="-r 30000/1001"
		# 1280x720 30fps
		level="3.1"
		# 1280x720 60fps
		#level="3.2"
	else
		if echo $filename | egrep "^(${shows})" >/dev/null 2>&1 ; then
			# crop to 4:3 1080p (1440x1080)
			filter="-vf yadif=0:-1:0,crop=in_h*(4/3):in_h"
		else
			# convert to 1080p via deinterlace
			filter="-vf yadif=0:-1:0"
		fi
		# 1920x1080 30fps
		# Samsung - Galaxy Tab A needs level 4.0
		level="4.0"
		# 1920x1080 30fps (higher bitrates)
		#level="4.1"
	fi

	queue_job
	"$ffmpeg" -hide_banner -i "$1" -vcodec libx264 -preset ${preset} $encode_opts -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
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
	"$ffmpeg" -hide_banner -i "$1" -vcodec libx264 -preset ${preset} $encode_opts -level ${level} -profile:v high -crf $crf $filter $movflags -acodec $audio_codec $size $aspect $frame_rate $time -y "$output" >>$results_file 2>&1
	rm "$1"
	remove_job
fi
