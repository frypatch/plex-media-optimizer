#! /usr/bin/env bash
# 
# Example usages:
# ---------------
#  bash dvd_rip.sh -help
#  bash dvd_rip.sh [directory]
#  bash dvd_rip.sh -dry [directory]
#  bash dvd_rip.sh -cleanup -skipDenoise [directory]
# 
# Some websites with background information on encoding videos
# ------------------------------------------------------------
# https://slhck.info/video/2017/02/24/crf-guide.html
# https://mattgadient.com/results-encoding-8-bit-video-at-81012-bit-in-handbrake-x264x265/
# https://www.reddit.com/r/Twitch/comments/c8ec2h/guide_x264_encoding_is_still_the_best_slow_isnt/
# 
# When to use 264 vs 265?
# -----------------------
# * Visual quality is the same for h264 and h265 at a given CRF.
# * h264 will let you encode the video 5x faster.
# * h264 will deliver the same visual quality as h265 when the bitrate to achieve a CRF value is below the bitrate threshold.
# * h265 will deliver 30%-50% more visual quality than h264 for a given bitrate.
# * h265 will cost 30% less to store than h264 for a given CRF
# 
# When to use 10bit vs 8bit
# -------------------------
# * Always scale videos in 10bit to reduce banding; use dither if you convert back to 8bit.
# * 10bit encoding will deliver 5%-10% more visual quality than 8bit encoding for a given bitrate.
# * media players almost never support 10bit h264 encoding
# * media players after 2018 almost always support 10bit h265 encoding
# 
# When to use slow vs faster?
# ---------------------------
# * Use `slow` whenever possible. If not possible then use `fast` with a larger result set.
# * `slow` will deliver more visual quality for a given bitrate
# * `slow` uses more complex algorithm so it will perserve details that `fast` doesn't look for regardless of bitrate.

###############################################
# Script constants to display text in different color
# echo needs to use the -e parameter for the colors to work
###############################################

# Set text to print out white on a red background.
ALERT_FONT='\033[97;101m'
# Set text to print out black on a yellow background.
INFO_FONT='\033[30;103m'
# Set text to print out black on a green background.
SUCCESS_FONT='\033[30;102m'
# Reset the text and background colors.
RESET_FONT='\033[0m'

###############################################
# Global variables to manage vedio output state.
###############################################

# the title
title="unknown"
tmpDir=""
originalVersion=""
optimizedVersion=""
downsampleVersion=""
filename=""

###############################################
# Input Parameters
###############################################

# the path to the directory to scan for video files to optimize: example: /media/Cinima
inputDir="unknown"
# set to apply a filter to titles that should be optimized
filter=".*"
# video bitrate
videoBitrate="1900"
# force 8bit video
force8bit="false"
# force AVC video
forceAvc="false"
# dry run; when true then just print the state of videos
dryRun="false"
# discard original; when true delete the original files once optimized versions have been produced.
discardOriginal="false"
# produce sample; when true just optimize the first 30 seconds. This is useful for testing.
produceSample="false"
# denoise; when true video will be denoised with nlmeans and dejittered.
denoise="true"
# stabilize; when true the video will be angularly stabilized.
stabilize="false"
# when truen then display the help message
help="false"

while [[ "$#" -ge 1 ]]; do
  if [ "$1" == "-h" ] || [ "$1" == "-help" ]; then
    help="true"
  elif [ "$1" == "-d" ] || [ "$1" == "-dry" ]; then
    dryRun="true"
  elif [ "$1" == "-s" ] || [ "$1" == "-sample" ]; then
    produceSample="true"
  elif [ "$1" == "-c" ] || [ "$1" == "-cleanup" ]; then
    discardOriginal="true"
  elif [ "$1" == "-force264" ] || [ "$1" == "-forceAvc" ]; then
    forceAvc="true"
  elif [ "$1" == "-force8bit" ]; then
    force8bit="true"
  elif [ "$1" == "-skipDenoise" ]; then
    denoise="false"
  elif [ "$1" == "-stabilize" ]; then
    stabilize="true"
  elif [ "$1" == "-filter" ] || [ "$1" == "-f" ]; then
    shift
    filter="$1"
  elif [ "$1" == "-bitrate" ]; then
    shift
    videoBitrate="$1"
  else
    inputDir="$1"
  fi
  shift
done
# prints help message to terminal
printHelp() {
  echo "usage: dvd_rip_2.sh [options] {input directory}"
  echo ""
  echo "Per-file main options:"
  echo "-h              same as -help"
  echo "-d              same as -dry"
  echo "-s              same as -sample"
  echo "-c              same as -cleanup"
  echo "-f [regex]      same as -filter [regex]"
  echo "-dry            prints the state of videos"
  echo "-sample         optimizes the first 30 seconds of the videos"
  echo "-cleanup        delete the original file[s] after producing its optimized version"
  echo "-bitrate        the capped video bitrate in kb/s (default is 1900)"
  echo "-force264       same as -forceAvc"
  echo "-forceAvc       force the optimized files to use AVC encoding (default is HEVC)"
  echo "-force8bit      force the optimized files to use 8 bit encoding (default is 10 bit)"
  echo "-stabilize      angularly stabilize the video (default is to not angularly stabilize the video, requires vidstab)"
  echo "-skipDenoise    do not denoise or dejitter the video (default is to lightly denoise with NLMeans and dejitter)"
  echo "-filter [regex] only optimize videos when their names match the supplied regex"
}
# main logic function
main () {
  echo "dry         $dryRun"
  echo "sample      $produceSample"
  echo "cleanup     $discardOriginal"
  echo "bitrate     $videoBitrate"
  echo "denoise     $denoise"
  echo "forceAvc    $forceAvc"
  echo "force8bit   $force8bit"
  echo "stabilize   $stabilize"
  echo "filter      $filter"
  echo "inputDir    $inputDir"
  for dir in "$(getInputDir)"/*/ ; do
    # everything before the last / is considered the title
    title=${dir%/*}
    # everything after the last / is considered the title
    title=${title##*/}
    if [[ $title =~ $filter ]]; then
      if [ -f "$(getInputDir)$(getTitle)/$(getTitle).mp4" ]; then
        filename="$(getInputDir)$(getTitle)/$(getTitle).mp4"
      elif [ -f "$(getInputDir)$(getTitle)/$(getTitle).m4v" ]; then
        filename="$(getInputDir)$(getTitle)/$(getTitle).m4v"
      elif [ -f "$(getInputDir)$(getTitle)/$(getTitle).mkv" ]; then
        filename="$(getInputDir)$(getTitle)/$(getTitle).mkv"
      elif [ -f "$(getInputDir)$(getTitle)/$(getTitle).webm" ]; then
        filename="$(getInputDir)$(getTitle)/$(getTitle).webm"
      else
        filename="unknown"
      fi
      if [ "$filename" != "unknown" ]; then
        mv "$filename" "$(getInputDir)/$(getTitle)/$(getTitle).mp4"
        filename="$(getInputDir)/$(getTitle)/$(getTitle).mp4"
        optimize
      elif [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt1.mp4" ] || [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt1.m4v" ] || [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt1.mkv" ] || [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt1.webm" ]; then
        concat
      fi
    else 
      echo "skipping $title due to filter."
    fi
  done
}
cut_scene () {
  local ORIGINAL_VERSION="${TMP_DIR}/original.mp4"
  local STABILIZE_VIDEO="$(getStabilize)"
  local INPUT_PIX_FMT="$(getInputPixFmt)"
  local VIDEO_FILTER=""
  if [ "$3" != "" ]; then
    VIDEO_FILTER="select='between(n,${1},${3})',setpts='PTS-STARTPTS'"
  else
    VIDEO_FILTER="select='gte(n,${1})',setpts='PTS-STARTPTS'"
  fi
  if [ "${INPUT_PIX_FMT}" != "yuv420p" ]; then
    VIDEO_FILTER="${VIDEO_FILTER},format=yuv420p"
  fi
  VIDEO_FILTER="${VIDEO_FILTER},nlmeans='1.0:7:5:3:3',format=yuv420p10le"
  local FFMPEG_SCENE_CUT_PARAMS=()
  FFMPEG_SCENE_CUT_PARAMS+=(-i "${ORIGINAL_VERSION}")
  FFMPEG_SCENE_CUT_PARAMS+=(-map "0:v:0")
  FFMPEG_SCENE_CUT_PARAMS+=(-vf "${VIDEO_FILTER}")
  FFMPEG_SCENE_CUT_PARAMS+=(-vsync 1)
  FFMPEG_SCENE_CUT_PARAMS+=(-vcodec "libx264")
  FFMPEG_SCENE_CUT_PARAMS+=(-crf "3")
  FFMPEG_SCENE_CUT_PARAMS+=(-preset "slow")
  FFMPEG_SCENE_CUT_PARAMS+=(-profile:v "high10")
  FFMPEG_SCENE_CUT_PARAMS+=(-level:v 6.1)
  FFMPEG_SCENE_CUT_PARAMS+=(-g 60)
  FFMPEG_SCENE_CUT_PARAMS+=(-sc_threshold 0)
  FFMPEG_SCENE_CUT_PARAMS+=(-an)
  FFMPEG_SCENE_CUT_PARAMS+=(-f "mp4")
  FFMPEG_SCENE_CUT_PARAMS+=(-y "${TMP_DIR}/scenes/pt${2}.m4v")
  if ffmpeg ${FFMPEG_SCENE_CUT_PARAMS[@]}; then
    local FFMPEG_ANALYZE_SCENE_PARAMS=()
    FFMPEG_ANALYZE_SCENE_PARAMS+=(-i "${TMP_DIR}/scenes/pt${2}.m4v")
    FFMPEG_ANALYZE_SCENE_PARAMS+=(-map "0:v:0")
    FFMPEG_ANALYZE_SCENE_PARAMS+=(-vf "vidstabdetect=stepsize=32")
    FFMPEG_ANALYZE_SCENE_PARAMS+=(-f null)
    FFMPEG_ANALYZE_SCENE_PARAMS+=(-)
    if ffmpeg ${FFMPEG_ANALYZE_SCENE_PARAMS[@]}; then
      local FFMPEG_STABILIZE_SCENE_PARAMS=()
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-i "${TMP_DIR}/scenes/pt${2}.m4v")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-map "0:v:0")
      if [ "${STABILIZE_VIDEO}" == "true" ]; then
        FFMPEG_STABILIZE_SCENE_PARAMS+=(-vf "vidstabtransform=zoom=0:optzoom=1:interpol=bicubic:smoothing=30:crop=black")
      else
        # setting maxangle=0 as even 3deg produced jello effects in Tears of Steel.
        # setting maxshift=24 to make sure that the video doesn't get too zoomed in.
        FFMPEG_STABILIZE_SCENE_PARAMS+=(-vf "vidstabtransform=zoom=0:optzoom=1:interpol=bicubic:smoothing=30:maxangle=0:maxshift=24:crop=black")
      fi
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-vcodec "libx264")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-crf "6")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-preset "slow")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-profile:v "high10")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-level:v 6.1)
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-g 60)
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-sc_threshold 0)
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-an)
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-f "mp4")
      FFMPEG_STABILIZE_SCENE_PARAMS+=(-y "${TMP_DIR}/scenes/stable${2}.mp4")
      if ffmpeg ${FFMPEG_STABILIZE_SCENE_PARAMS[@]}; then
        rm "${TMP_DIR}/scenes/pt${2}.m4v"
        mv "${TMP_DIR}/scenes/stable${2}.mp4" "${TMP_DIR}/scenes/pt${2}.m4v"
        echo "successful split and stabilized scene ${TMP_DIR}/scenes/pt${2}"
      else
        echo "failed to stabilize scene ${TMP_DIR}/scenes/pt${2}"
        rm "${TMP_DIR}/scenes/stable${2}.mp4"
      fi
    else
      echo "failed to detect stabilization data for scene ${TMP_DIR}/scenes/pt${2}"
    fi
  else
    echo "failed to split scene ${TMP_DIR}/scenes/pt${2}"
  fi
}
denoise() {
  local TMP_DIR="$(getTmpDir)"
  local ORIGINAL_VERSION="${TMP_DIR}/original.mp4"
  local DENOISED_VERSION="${TMP_DIR}/denoised.mp4"
  if [ ! -f "${ORIGINAL_VERSION}" ]; then
    cp "${1}" "${ORIGINAL_VERSION}"
  fi
  local SCENE_DIR="${TMP_DIR}/scenes"
  mkdir -p "${SCENE_DIR}"
  local FROM_FRAME=0
  ffprobe -select_streams v -show_entries frame=pkt_pts -of compact=p=0:nk=1 -f lavfi "movie=$ORIGINAL_VERSION,setpts=N+1,select=gt(scene\,.2)" > "${TMP_DIR}/scenes.txt"
  local FROM_FRAME=0
  local COUNT=0
  SCENES=`cat "${TMP_DIR}/scenes.txt"`
  for SCENE_INDEX in $SCENES; do
    cut_scene $(echo "$FROM_FRAME-1" | bc) $(echo "1000000+$COUNT" | bc) $(echo "$SCENE_INDEX-2" | bc)
    FROM_FRAME=${SCENE_INDEX}
    COUNT=$(echo "$COUNT+1" | bc)
  done
  if [ $FROM_FRAME != 0 ]; then
    cut_scene $FROM_FRAME 9999999
  fi
  for f in "${TMP_DIR}/scenes"/*.m4v; do echo "file '$f'" >> "${TMP_DIR}/mylist.txt"; done
  local FFMPEG_CONCAT_PARAMS=()
  FFMPEG_CONCAT_PARAMS+=(-f "concat")
  FFMPEG_CONCAT_PARAMS+=(-safe "0")
  FFMPEG_CONCAT_PARAMS+=(-i "${TMP_DIR}/mylist.txt")
  FFMPEG_CONCAT_PARAMS+=(-i "${ORIGINAL_VERSION}")
  FFMPEG_CONCAT_PARAMS+=(-map "0:v:0")
  FFMPEG_CONCAT_PARAMS+=(-c:v copy)
  FFMPEG_CONCAT_PARAMS+=(-map "1:a:0")
  FFMPEG_CONCAT_PARAMS+=(-c:a aac)
  FFMPEG_CONCAT_PARAMS+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
  FFMPEG_CONCAT_PARAMS+=(-ab "192k")
  FFMPEG_CONCAT_PARAMS+=(-ac 2)
  FFMPEG_CONCAT_PARAMS+=(-ar 44100)
  FFMPEG_CONCAT_PARAMS+=(-y)
  FFMPEG_CONCAT_PARAMS+=("${DENOISED_VERSION}")
  if ffmpeg ${FFMPEG_CONCAT_PARAMS[@]}; then
    echo "successful stabilization!!"
  else
    echo "failed stabilization :-("

  fi
  rm -rf "${TMP_DIR}/scenes"
}
optimize () {
  local INPUT_TITLE="$(getTitle)"
  local INPUT_WIDTH="$(getInputWidth)"
  local INPUT_HEIGHT="$(getInputHeight)"
  if [ "${INPUT_WIDTH}" == "1280" ] && [ "${INPUT_HEIGHT}" == "720" ]; then
    echo -e "${SUCCESS_FONT}### ${INPUT_TITLE}.mp4 has already been optimized.${RESET_FONT}"
    downsample
  else
    echo -e "${ALERT_FONT}### Optimizing ${INPUT_TITLE}.mp4${RESET_FONT}"
    initTmpDirs
    local INPUT_FPS="$(getInputFps)"
    local IS_DRY_RUN="$(getDryRun)"
    local DENOISE_VIDEO="$(getDenoise)"
    local STABILIZE_VIDEO="$(getStabilize)"
    local INPUT_DIR="$(getInputDir)"
    local TMP_DIR="$(getTmpDir)"
    local VIDEO_BITRATE="$(getVideoBitrate)"
    local VIDEO_BUFFER_BITRATE="$(getVideoBufferBitrate)"
    local ORIGINAL_VERSION="${TMP_DIR}/original.mp4"
    local DENOISED_VERSION="${TMP_DIR}/denoised.mp4"
    local OPTIMIZED_VERSION="${TMP_DIR}/optimized.mp4"
    echo "${ORIGINAL_VERSION}"
    echo "${DENOISED_VERSION}"
    echo "${OPTIMIZED_VERSION}"
    if [ "${IS_DRY_RUN}" == "false" ]; then
      if [ "${DENOISE_VIDEO}" == "true" ] || [ "${STABILIZE_VIDEO}" == "true" ]; then
        denoise "${filename}"
      fi
    fi
    local INPUT_PIX_FMT="$(getInputPixFmt)"
    local INPUT_COLOR_PRIMITIVES="$(getInputColorPrimitives)"
    local INPUT_VIDEO_CODEC_LIB="$(getVideoCodecLib)"
    local INPUT_VIDEO_PROFILE="$(getVideoProfile)"
    local FORCE_AVC="$(getForceAvc)"
    local INPUT_AUDIO_CHANNELS="$(getInputAudioChannels)"
    local IS_FDK_AAC_INSTALLED="$(isFdkAacInstalled)"
    
    local FFMPEG_OPTIMIZE_PARAMS=()
    if [ -f "${DENOISED_VERSION}" ]; then
      FFMPEG_OPTIMIZE_PARAMS+=(-i "${DENOISED_VERSION}")
    else
      FFMPEG_OPTIMIZE_PARAMS+=(-i "${ORIGINAL_VERSION}")
    fi
    FFMPEG_OPTIMIZE_PARAMS+=(-i "${ORIGINAL_VERSION}")
    if [ "$(getProduceSample)" == "true" ]; then
      echo -e "${ALERT_FONT}### Producing 30 second sample.${RESET_FONT}"
      FFMPEG_OPTIMIZE_PARAMS+=(-ss "00:00:00")
      FFMPEG_OPTIMIZE_PARAMS+=(-to "00:00:30")
    fi
    FFMPEG_OPTIMIZE_PARAMS+=(-map "0:v:0")
    FFMPEG_OPTIMIZE_PARAMS+=(-map "-0:t") # remove attachments
    # currently not sure what format the video uses because we could be using the denoised video or the original video.
    local VIDEO_FILTER="format=yuv420p10le,"
#    if [ "${INPUT_PIX_FMT}" != "yuv420p10le" ]; then
#      VIDEO_FILTER="${VIDEO_FILTER}format=yuv420p10le,"
#    fi
    if [ "${INPUT_COLOR_PRIMITIVES}" == "unknown" ]; then
      if [ "${INPUT_HEIGHT}" -gt "720" ]; then
        VIDEO_FILTER="${VIDEO_FILTER}colorspace=bt709:iall=bt2020:fast=1,"
      elif [ "${INPUT_HEIGHT}" -gt "480" ]; then
        VIDEO_FILTER="${VIDEO_FILTER}colorspace=bt709:iall=bt709:fast=1,"
      elif [ "${INPUT_FPS}" == "25/1" ] || [ "${INPUT_FPS}" == "50/1" ]; then
        VIDEO_FILTER="${VIDEO_FILTER}colorspace=bt709:iall=bt601-6-625:fast=1,"
      else
        VIDEO_FILTER="${VIDEO_FILTER}colorspace=bt709:iall=bt601-6-525:fast=1,"
      fi
    elif [ "${INPUT_COLOR_PRIMITIVES}" != "bt709" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}colorspace=bt709:iall=${INPUT_COLOR_PRIMITIVES}:fast=1,"
    fi
    if [ "${INPUT_WIDTH}" -lt "1280" ] && [ "${INPUT_HEIGHT}" -lt "720" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_WIDTH}" -lt "1280" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih:flags=neighbor,transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_HEIGHT}" -lt "720" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',"
    fi
    if [ "${INPUT_WIDTH}" -lt "640" ] && [ "${INPUT_HEIGHT}" -lt "360" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_WIDTH}" -lt "640" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih:flags=neighbor,transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_HEIGHT}" -lt "360" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',"
    fi
    if [ "$(getForce8bit)" != "true" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=1280:h=720:flags=print_info+spline+full_chroma_inp+full_chroma_int,"
    elif [ "$(isZscaleInstalled)" == "true" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}zscale=w=1280:h=720:f=spline36:r=full:dither=ordered,format=yuv420p,"
    else
      echo -e "${INFO_FONT}### ZScale is not installed, falling back to Scale.${RESET_FONT}"
      echo -e "${INFO_FONT}###   To install ZScale on MacOS:${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew uninstall ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew tap homebrew-ffmpeg/ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-zimg --HEAD${RESET_FONT}"
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=1280:h=720:flags=print_info+spline+full_chroma_inp+full_chroma_int,format=yuv420p,"
    fi
    VIDEO_FILTER="${VIDEO_FILTER}hqdn3d=1:1:7:7"
    echo -e "${INFO_FONT}### Video Filter: $VIDEO_FILTER${RESET_FONT}"
    FFMPEG_OPTIMIZE_PARAMS+=(-vf "$VIDEO_FILTER")
    FFMPEG_OPTIMIZE_PARAMS+=(-vsync 1)
    FFMPEG_OPTIMIZE_PARAMS+=(-vcodec "${INPUT_VIDEO_CODEC_LIB}")
    echo -e "${INFO_FONT}### Video Codec: ${INPUT_VIDEO_CODEC_LIB}${RESET_FONT}"
    FFMPEG_OPTIMIZE_PARAMS+=(-r "${INPUT_FPS}")
    echo -e "${INFO_FONT}### Video FPS: ${INPUT_FPS}${RESET_FONT}"
    FFMPEG_OPTIMIZE_PARAMS+=(-crf "16")
    echo -e "${INFO_FONT}### Video CRF: 16${RESET_FONT}"
    FFMPEG_OPTIMIZE_PARAMS+=(-maxrate "${VIDEO_BITRATE}k")
    FFMPEG_OPTIMIZE_PARAMS+=(-bufsize "${VIDEO_BUFFER_BITRATE}k")
    FFMPEG_OPTIMIZE_PARAMS+=(-preset "slow")
    echo -e "${INFO_FONT}### Video Preset: slow${RESET_FONT}"
    FFMPEG_OPTIMIZE_PARAMS+=(-profile:v "${INPUT_VIDEO_PROFILE}")
    if [ "${FORCE_AVC}" == "true" ]; then
      FFMPEG_OPTIMIZE_PARAMS+=(-level:v 4.0)
      FFMPEG_OPTIMIZE_PARAMS+=(-g 60)
      FFMPEG_OPTIMIZE_PARAMS+=(-sc_threshold 0)
    else
      FFMPEG_OPTIMIZE_PARAMS+=(-x265-params "level-idc=40:keyint=60:min-keyint=60:scenecut=0")
    fi
    FFMPEG_OPTIMIZE_PARAMS+=(-map "1:a:0")
    FFMPEG_OPTIMIZE_PARAMS+=(-c:a aac)
    FFMPEG_OPTIMIZE_PARAMS+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
    if [ "${INPUT_AUDIO_CHANNELS}" == "1" ] || [ "${INPUT_AUDIO_CHANNELS}" == "2" ]; then
      FFMPEG_OPTIMIZE_PARAMS+=(-ab "192k")
      FFMPEG_OPTIMIZE_PARAMS+=(-ac 2)
    else
      FFMPEG_OPTIMIZE_PARAMS+=(-ab "448k")
      FFMPEG_OPTIMIZE_PARAMS+=(-ac "${INPUT_AUDIO_CHANNELS}")
    fi
    FFMPEG_OPTIMIZE_PARAMS+=(-ar 44100)
    FFMPEG_OPTIMIZE_PARAMS+=(-movflags +faststart)
    FFMPEG_OPTIMIZE_PARAMS+=(-f "mp4")
    FFMPEG_OPTIMIZE_PARAMS+=(-y "${OPTIMIZED_VERSION}")
    if [ "${IS_FDK_AAC_INSTALLED}" == "false" ]; then
      echo -e "${INFO_FONT}### AAC HE V2 is not installed, falling back to AAC Mono for 48k audio version.${RESET_FONT}"
      echo -e "${INFO_FONT}###   To install AAC HE V2 on MacOS:${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew uninstall ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew tap homebrew-ffmpeg/ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac --HEAD${RESET_FONT}"
    fi
    if [ "${IS_DRY_RUN}" == "false" ]; then
      if [ ! -f "${ORIGINAL_VERSION}" ]; then
        cp "${filename}" "${ORIGINAL_VERSION}"
      fi
      if ffmpeg ${FFMPEG_OPTIMIZE_PARAMS[@]}; then
        mkdir -p "$(getInputDir)$(getTitle)/orig"
        mv "$filename" "${INPUT_DIR}/${INPUT_TITLE}/orig/${INPUT_TITLE}.mp4"
        if [ "$(getDiscardOriginal)" == "true" ]; then
          rm -rf "${INPUT_DIR}/${INPUT_TITLE}/orig"
        fi
        cp "$OPTIMIZED_VERSION" "${INPUT_DIR}/${INPUT_TITLE}/${INPUT_TITLE}.mp4"
        rm -rf "$(getTmpDir)"
        downsample
      fi
    fi
  fi
}
downsample () {
    if [ -f "$(getInputDir)/$(getTitle)/$(getTitle) - 48k audio.mp4" ]; then
        echo -e "${SUCCESS_FONT}### $(getTitle).mp4 audio has already been downsampled.${RESET_FONT}"
    else
        echo -e "${ALERT_FONT}### Downsample $(getTitle).mp4 audio to 48k.${RESET_FONT}"
        initTmpDirs
        originalVersion="$(getTmpDir)/original.mp4"
        downsampleVersion="$(getTmpDir)/downsample.mp4"
        local FFMPEG_DOWNSAMPLE_PARAMS=()
        FFMPEG_DOWNSAMPLE_PARAMS+=(-i "$originalVersion")
        FFMPEG_DOWNSAMPLE_PARAMS+=(-map "0:v")
        FFMPEG_DOWNSAMPLE_PARAMS+=(-map "0:a")
        FFMPEG_DOWNSAMPLE_PARAMS+=(-c:v "copy")
        if [ "${IS_FDK_AAC_INSTALLED}" == "true" ]; then
          FFMPEG_DOWNSAMPLE_PARAMS+=(-c:a libfdk_aac)
          FFMPEG_DOWNSAMPLE_PARAMS+=(-profile:a aac_he_v2)
          FFMPEG_DOWNSAMPLE_PARAMS+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
          FFMPEG_DOWNSAMPLE_PARAMS+=(-ac 2)
        else
          FFMPEG_DOWNSAMPLE_PARAMS+=(-c:a aac)
          FFMPEG_DOWNSAMPLE_PARAMS+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
          FFMPEG_DOWNSAMPLE_PARAMS+=(-ac 1)
        fi
        FFMPEG_DOWNSAMPLE_PARAMS+=(-ab "48k")
        FFMPEG_DOWNSAMPLE_PARAMS+=(-ar 44100)
        FFMPEG_DOWNSAMPLE_PARAMS+=(-movflags +faststart)
        FFMPEG_DOWNSAMPLE_PARAMS+=(-f "mp4")
        FFMPEG_DOWNSAMPLE_PARAMS+=(-y "$downsampleVersion")
        if [ "${IS_DRY_RUN}" == "false" ]; then
          cp "$filename" "$originalVersion"
          if ffmpeg ${FFMPEG_DOWNSAMPLE_PARAMS[@]}; then
            cp "$downsampleVersion" "$(getInputDir)/$(getTitle)/$(getTitle) - 48k audio.mp4"
          fi
          rm -rf "$(getTmpDir)"
        fi
    fi
}
concat () {
  initTmpDirs
  local i="0"
  local count="10"
  mkdir -p "$(getInputDir)$(getTitle)/orig"
  while [ "${i}" -lt "90" ]; do
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mp4" ]; then
      echo "copying $(getTitle) - pt${i}.mp4 to $(getTmpDir)/pt${count}.m4v"
      cp "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mp4" "$(getTmpDir)/pt${count}.m4v"
      mv "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mp4" "$(getInputDir)$(getTitle)/orig/$(getTitle) - pt${i}.mp4"
      count=$(( $count + 1 ))
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.m4v" ]; then
      echo "copying $(getTitle) - pt${i}.m4v to $(getTmpDir)/pt${count}.m4v"
      cp "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.m4v" "$(getTmpDir)/pt${count}.m4v"
      mv "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.m4v" "$(getInputDir)$(getTitle)/orig/$(getTitle) - pt${i}.m4v"
      count=$(( $count + 1 ))
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mkv" ]; then
      echo "copying $(getTitle) - pt${i}.mkv to $(getTmpDir)/pt${count}.m4v"
      cp "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mkv" "$(getTmpDir)/pt${count}.m4v"
      mv "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mkv" "$(getInputDir)$(getTitle)/orig/$(getTitle) - pt${i}.mkv"
      count=$(( $count + 1 ))
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.webm" ]; then
      echo "copying $(getTitle) - pt${i}.webm to $(getTmpDir)/pt${count}.m4v"
      cp "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.webm" "$(getTmpDir)/pt${count}.m4v"
      mv "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.webm" "$(getInputDir)$(getTitle)/orig/$(getTitle) - pt${i}.webm"
      count=$(( $count + 1 ))
    fi
    i=$(( $i + 1 ))
  done
  echo -e "${ALERT_FONT}### Concat videos parts into $(getTitle).mp4${RESET_FONT}"
  local fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$(getTmpDir)/pt10.m4v") 2>&1)
  fps=$(echo "10*$fps" | bc)
  local avg_fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=avg_frame_rate "$(getTmpDir)/pt10.m4v") 2>&1)
  avg_fps=$(echo "10*$avg_fps" | bc)
  local INPUT_FPS="unknown"
  if [ "$fps" == "240" ]; then
    INPUT_FPS="24/1"
  elif [ "$fps" == "250" ]; then
    INPUT_FPS="25/1"
  elif [ "$fps" == "300" ]; then
    INPUT_FPS="30/1"
  elif [ "$fps" == "480" ]; then
    INPUT_FPS="24/1"
  elif [ "$fps" == "500" ]; then
    INPUT_FPS="50/1"
  elif [ "$fps" == "600" ]; then
    INPUT_FPS="30/1"
  elif [ "$fps" -lt "243" ]; then
    INPUT_FPS="24000/1001"
  elif [ "$fps" -lt "260" ]; then
    INPUT_FPS="25/1"
  elif [ "$fps" -lt "460" ]; then
    INPUT_FPS="30000/1001"
  elif [ "$fps" -lt "490" ]; then
    INPUT_FPS="24000/1001"
  elif [ "$fps" -lt "510" ]; then
    INPUT_FPS="25/1"
  elif [ "$fps" -lt "620" ]; then
    INPUT_FPS="30000/1001"
  elif [ "$avg_fps" -lt "243" ]; then
    INPUT_FPS="24000/1001"
  elif [ "$avg_fps" -lt "260" ]; then
    INPUT_FPS="25/1"
  elif [ "$avg_fps" -lt "460" ]; then
    INPUT_FPS="30000/1001"
  elif [ "$avg_fps" -lt "490" ]; then
    INPUT_FPS="24000/1001"
  elif [ "$avg_fps" -lt "510" ]; then
    INPUT_FPS="25/1"
  else
    INPUT_FPS="30000/1001"
  fi
  # lets iterate over all the video parts to figure out a width and height to scale to that is larger than 720p.
  #   this lets know that the video with the largest vertical resolution will maximize the vertical resolution 
  #   and the video with the largest horizontal resolution will maximize the horizontal resolution.
  local MAX_INPUT_AUDIO_CHANNELS="1"
  local MAX_INPUT_HEIGHT="0"
  local MAX_INPUT_DAR="0"
  for origPart in "$(getTmpDir)"/*.m4v; do
    local INPUT_AUDIO_CHANNELS=$((ffprobe -v error -select_streams a:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=channels "${origPart}") 2>&1)
    local INPUT_HEIGHT=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "${origPart}") 2>&1)
    local INPUT_DAR=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=display_aspect_ratio "${origPart}") 2>&1)
    # everything before the last : is considered the DAR's width
    local INPUT_DAR_WIDTH="${INPUT_DAR%:*}"
    # everything after the last :  is considered the DAR's height
    local INPUT_DAR_HEIGHT=${INPUT_DAR##*:}
    INPUT_DAR=$(echo "1000*${INPUT_DAR_WIDTH}/${INPUT_DAR_HEIGHT}" | bc)
    if [ "${INPUT_HEIGHT}" -gt "${MAX_INPUT_HEIGHT}" ]; then
      MAX_INPUT_HEIGHT="${INPUT_HEIGHT}"
    fi
    if [ "${INPUT_DAR}" -gt "${MAX_INPUT_DAR}" ]; then
      MAX_INPUT_DAR="${INPUT_DAR}"
    fi
    if [ "${INPUT_AUDIO_CHANNELS}" -gt "${MAX_INPUT_AUDIO_CHANNELS}" ]; then
      MAX_INPUT_AUDIO_CHANNELS="${INPUT_AUDIO_CHANNELS}"
    fi
  done
  while [ "${MAX_INPUT_HEIGHT}" -lt "721" ]; do
    MAX_INPUT_HEIGHT=$(echo "2*${MAX_INPUT_HEIGHT}" | bc)
  done
  local MAX_INPUT_WIDTH=$(echo "${MAX_INPUT_DAR}*${MAX_INPUT_HEIGHT}/1000" | bc)
  # for each video, lets do some processing and then scale it to fit in the MAX_INPUT_WIDTH by MAX_INPUT_HEIGHT box.
  for origPart in "$(getTmpDir)"/*.m4v; do
    local INPUT_WIDTH=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "${origPart}") 2>&1)
    local INPUT_HEIGHT=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "${origPart}") 2>&1)
    local INPUT_PIX_FMT=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=pix_fmt "${origPart}") 2>&1)
    local INPUT_COLOR_PRIMITIVES=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=color_primaries "${origPart}") 2>&1)
    local ffmpegParams=()
    ffmpegParams+=(-i "${origPart}")
    if [ "$(getProduceSample)" == "true" ]; then
      ffmpegParams+=(-ss "00:00:00")
      ffmpegParams+=(-to "00:00:30")
    fi
    ffmpegParams+=(-map "0:v:0")
    ffmpegParams+=(-map "-0:t") # remove attachments
    local videoFilter=""
    if [ "$(getDenoise)" == "true" ]; then
      if [ "${INPUT_PIX_FMT}" != "yuv420p" ]; then
        videoFilter="${videoFilter}format=yuv420p,"
      fi
      videoFilter="${videoFilter}nlmeans='1.0:7:5:3:3',format=yuv420p10le"
    else
      echo -e "${ALERT_FONT}### Skipping denoise step. Did you remember to denoise your source with NLMeans?${RESET_FONT}"
      if [ "${INPUT_PIX_FMT}" != "yuv420p10le" ]; then
        videoFilter="${videoFilter}format=yuv420p10le,"
      fi
    fi
    if [ "${INPUT_COLOR_PRIMITIVES}" == "unknown" ]; then
      if [ "${INPUT_HEIGHT}" -gt "720" ]; then
        videoFilter="${videoFilter}colorspace=bt709:iall=bt2020:fast=1,"
      elif [ "${INPUT_HEIGHT}" -gt "480" ]; then
        videoFilter="${videoFilter}colorspace=bt709:iall=bt709:fast=1,"
      elif [ "${INPUT_FPS}" == "25/1" ] || [ "${INPUT_FPS}" == "50/1" ]; then
        videoFilter="${videoFilter}colorspace=bt709:iall=bt601-6-625:fast=1,"
      else
        videoFilter="${videoFilter}colorspace=bt709:iall=bt601-6-525:fast=1,"
      fi
    elif [ "${INPUT_COLOR_PRIMITIVES}" != "bt709" ]; then
      videoFilter="${videoFilter}colorspace=bt709:iall=${INPUT_COLOR_PRIMITIVES}:fast=1,"
    fi
    if [ "${INPUT_WIDTH}" -lt "1281" ] && [ "${INPUT_HEIGHT}" -lt "721" ]; then
      videoFilter="${videoFilter}scale=w=iw*2:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_WIDTH}" -lt "1281" ]; then
      videoFilter="${videoFilter}scale=w=iw*2:h=ih:flags=neighbor,transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_HEIGHT}" -lt "721" ]; then
      videoFilter="${videoFilter}scale=w=iw:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',"
    fi
    if [ "${INPUT_WIDTH}" -lt "641" ] && [ "${INPUT_HEIGHT}" -lt "361" ]; then
      videoFilter="${videoFilter}scale=w=iw*2:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_WIDTH}" -lt "641" ]; then
      videoFilter="${videoFilter}scale=w=iw*2:h=ih:flags=neighbor,transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${INPUT_HEIGHT}" -lt "361" ]; then
      videoFilter="${videoFilter}scale=w=iw:h=ih*2:flags=neighbor,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',"
    fi
    videoFilter="${videoFilter}scale=(iw*sar)*min(${MAX_INPUT_WIDTH}/(iw*sar)\,${MAX_INPUT_HEIGHT}/ih):ih*min(${MAX_INPUT_WIDTH}/(iw*sar)\,${MAX_INPUT_HEIGHT}/ih):flags=print_info+spline+full_chroma_inp+full_chroma_int,"
    if [ "$(getForce8bit)" == "true" ]; then
      videoFilter="${videoFilter}format=yuv420p,"
    fi
    videoFilter="${videoFilter}pad=${MAX_INPUT_WIDTH}:${MAX_INPUT_HEIGHT}:(${MAX_INPUT_WIDTH}-iw*min(${MAX_INPUT_WIDTH}/iw\,${MAX_INPUT_HEIGHT}/ih))/2:(${MAX_INPUT_WIDTH}-ih*min(${MAX_INPUT_WIDTH}/iw\,${MAX_INPUT_HEIGHT}/ih))/2"
    ffmpegParams+=(-vf "${videoFilter}")
    ffmpegParams+=(-vsync 1)
    ffmpegParams+=(-vcodec "libx264")
    ffmpegParams+=(-r "${INPUT_FPS}")
    ffmpegParams+=(-crf "6")
    ffmpegParams+=(-preset "slow")
    ffmpegParams+=(-profile:v "high10")
    ffmpegParams+=(-level:v 6.1)
    ffmpegParams+=(-g 60)
    ffmpegParams+=(-sc_threshold 0)
    ffmpegParams+=(-map "0:a:0")
    ffmpegParams+=(-c:a aac)
    ffmpegParams+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
    ffmpegParams+=(-ab "600k")
    ffmpegParams+=(-ac "${MAX_INPUT_AUDIO_CHANNELS}")
    ffmpegParams+=(-ar 44100)
    ffmpegParams+=(-f "mp4")
    ffmpegParams+=(-y "${origPart}.mp4")
    if ffmpeg ${ffmpegParams[@]}; then
      echo "successful conversion"
    else
      echo "failed conversion"
    fi
  done
  # with a bash for loop
  for f in "$(getTmpDir)"/*.mp4; do echo "file '$f'" >> "$(getTmpDir)/mylist.txt"; done
  ffmpeg -f concat -safe 0 -i "$(getTmpDir)/mylist.txt" -c copy "$(getInputDir)$(getTitle)/$(getTitle).mp4"
  # cleanup
  rm -rf "$(getTmpDir)"
  if [ "$(getDiscardOriginal)" == "true" ]; then
    rm -rf "$(getInputDir)$(getTitle)/orig"
  fi
  # now run the joined video through the normal scaling process so that we can optimially assign bitrate and populate the video buffer.
  filename="$(getInputDir)$(getTitle)/$(getTitle).mp4"
  initTmpDirs
  optimize
}
# initiate the temporary directories
initTmpDirs () {
	# create a temp directory if one does not exist
	tmpDir=$(mktemp -d 2>/dev/null || mktemp -d -t 'pleximize')
	# create secondary directory in temp directory
	mkdir -p "$tmpDir/tmp"
}
getFilename () {
        local theFilename=""
        for extension in {mp4,m4v,mkv,webm}; do
                for aFilename in "$(getInputDir)$(getTitle)"/*.$extension; do
                        if [ -f "$(getInputDir)$(getTitle)/$(getTitle).$extension" ]; then
                                theFilename=$aFilename
                        fi
                done
        done
        echo $theFilename
}
## GETTERS ##
# get the temp directory
getTmpDir () {
  echo $tmpDir
}
# returns the video bitrate
getVideoBitrate() {
  echo ${videoBitrate}
}
# returns the video buffer bitrate
getVideoBufferBitrate() {
  echo $(echo "${videoBitrate}*2" | bc)
}
# returns true when video output should be 8 bit
getForce8bit () {
  echo $force8bit
}
# returns true when video output should be encoded in AVC
getForceAvc () {
  echo $forceAvc
}
# returns true when we should display the help message.
getHelp () {
  echo $help
}
# returns true when we should just print what will happen without actually executing ffmpeg
getDryRun () {
  echo $dryRun
}
# returns true when the original files should be discarded
getDiscardOriginal () {
  echo $discardOriginal
}
# returns true when we should just optimize the first 30 seconds. This is useful for testing.
getProduceSample () {
  echo $produceSample
}
# returns true when the video should be denoised.
getDenoise() {
  echo $denoise
}
# returns true when the video should be stabilized.
getStabilize() {
  echo $stabilize
}
# get the video profile
getVideoProfile () {
    if [ "$(getForce8bit)" == "true" ]; then
        echo "main"
    elif [ "$(getForceAvc)" == "true" ]; then
        echo "high10"
    else
        echo "main10"
    fi
}
getPixFmts () {
  if [ "$(getForce8bit)" == "true" ]; then
    echo "yuv420p"
  else
    echo "yuv420p10le"
  fi
}
# get title
getTitle () {
  echo $title
}
# get the video codec
getVideoCodec () {
  if [ "$(getForceAvc)" == "true" ]; then
    echo "264"
  else
    echo "265"
  fi
}
# get the video codec library
getVideoCodecLib () {
	if [ "$(getForceAvc)" == "true" ]; then
		echo "libx264"
	else
		echo "libx265"
	fi
}
# get the input file
getInputDir () {
	echo $inputDir
}
# get the input file's audio channel
getInputAudioChannels () {
        local audioChannels=$((ffprobe -v error -select_streams a:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=channels "$filename") 2>&1)
        echo $audioChannels
}
# get the input file's width
getInputWidth () {
        local width=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "$filename") 2>&1)
        echo $width
}
# get the input file's height
getInputHeight () {
        local height=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "$filename") 2>&1)
        echo $height
}
getInputPixFmt () {
        local pixFmt=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=pix_fmt "$filename") 2>&1)
        echo $pixFmt
}
getInputColorPrimitives() {
        local colorPrimitives=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=color_primaries "$filename") 2>&1)
        echo $colorPrimitives
}
# get the input file's DAR
getInputDar () {
        local dar=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=display_aspect_ratio "$filename") 2>&1)
        # everything before the last : is considered the DAR's width
        local darWidth="${dar%:*}"
        # everything after the last :  is considered the DAR's height
        local darHeight=${dar##*:}
        dar="$darWidth/$darHeight"
        echo $dar
}
# get the input file's FPS
getInputFps () {
        local fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$filename") 2>&1)
        fps=$(echo "10*$fps" | bc)
        local avg_fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=avg_frame_rate "$filename") 2>&1)
        avg_fps=$(echo "10*$avg_fps" | bc)
        if [ "$fps" == "240" ]; then
          echo "24/1"
        elif [ "$fps" == "250" ]; then
          echo "25/1"
        elif [ "$fps" == "300" ]; then
          echo "30/1"
        elif [ "$fps" == "480" ]; then
          echo "24/1"
        elif [ "$fps" == "500" ]; then
          echo "25/1"
        elif [ "$fps" == "600" ]; then
          echo "30/1"
        elif [ "$fps" -lt "243" ]; then
          echo "24000/1001"
        elif [ "$fps" -lt "260" ]; then
          echo "25/1"
        elif [ "$fps" -lt "460" ]; then
          echo "30000/1001"
        elif [ "$fps" -lt "490" ]; then
          echo "24000/1001"
        elif [ "$fps" -lt "510" ]; then
          echo "25/1"
        elif [ "$fps" -lt "620" ]; then
          echo "30000/1001"
        elif [ "$avg_fps" -lt "243" ]; then
          echo "24000/1001"
        elif [ "$avg_fps" -lt "260" ]; then
          echo "25/1"
        elif [ "$avg_fps" -lt "460" ]; then
          echo "30000/1001"
        elif [ "$avg_fps" -lt "490" ]; then
          echo "24000/1001"
        elif [ "$avg_fps" -lt "510" ]; then
          echo "25/1"
        else
          echo "30000/1001"
        fi
}
isZscaleInstalled () {
        local isZscaleInstalled=$((ffmpeg -version) 2>&1)
        if [[ "$isZscaleInstalled" == *"--enable-libzimg"* ]]; then
                echo "true"
        else
                echo "false"
        fi
}
isFdkAacInstalled () {
        local isFdkAacInstalled=$((ffmpeg -version) 2>&1)
        if [[ "$isFdkAacInstalled" == *"--enable-libfdk-aac"* ]]; then
                echo "true"
        else
                echo "false"
        fi
}
# when the help parameter is set then print the help documentation; otherwise run the main logic.
if [ "$(getHelp)" == "true" ]; then
  printHelp
else
  main
fi