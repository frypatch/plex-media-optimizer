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
# when true then display the help message
help="false"
# the preset to use. Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo
preset="slow"

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
  elif [ "$1" == "-preset" ] || [ "$1" == "-p" ]; then
    shift
    preset="$1"
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
  echo "-h                  same as -help"
  echo "-d                  same as -dry"
  echo "-s                  same as -sample"
  echo "-c                  same as -cleanup"
  echo "-f [regex]          same as -filter [regex]"
  echo "-p [selection]      same as -preset [selection]"
  echo "-dry                prints the state of videos"
  echo "-sample             optimizes the first 30 seconds of the videos"
  echo "-cleanup            delete the original file[s] after producing its optimized version"
  echo "-bitrate            the capped video bitrate in kb/s (default is 1900)"
  echo "-force264           same as -forceAvc"
  echo "-forceAvc           force the optimized files to use AVC encoding (default is HEVC)"
  echo "-force8bit          force the optimized files to use 8 bit encoding (default is 10 bit)"
  echo "-stabilize          angularly stabilize the video (default is to not angularly stabilize the video, requires vidstab)"
  echo "-skipDenoise        do not denoise or dejitter the video (default is to lightly denoise with NLMeans and dejitter)"
  echo "-filter [regex]     only optimize videos when their names match the supplied regex"
  echo "-preset [selection] what preset value to use. options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo"
}
# main logic function
main () {
  echo -e "${SUCCESS_FONT}dry         ${dryRun}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}sample      ${produceSample}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}cleanup     ${discardOriginal}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}bitrate     ${videoBitrate}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}denoise     ${denoise}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}forceAvc    ${forceAvc}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}force8bit   ${force8bit}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}stabilize   ${stabilize}${RESET_FONT}"
  if [ "$(isFdkAacInstalled)" == "true" ]; then
    echo -e "${SUCCESS_FONT}has fdk aac $(isFdkAacInstalled)${RESET_FONT}"
  else
    echo -e "${ALERT_FONT}has fdk aac $(isFdkAacInstalled)${RESET_FONT}"
  fi
  if [ "$(isLibVidStabInstalled)" == "true" ]; then
    echo -e "${SUCCESS_FONT}has vidstab $(isLibVidStabInstalled)${RESET_FONT}"
  else
    echo -e "${ALERT_FONT}has vidstab $(isLibVidStabInstalled)${RESET_FONT}"
  fi
  echo -e "${SUCCESS_FONT}preset      ${preset}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}filter      ${filter}${RESET_FONT}"
  echo -e "${SUCCESS_FONT}inputDir    ${inputDir}${RESET_FONT}"
  echo -e "------------------------"
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
getVideoFilter() {
  local FORCE_720P=${1}
  local FILE_NAME=${2}
  local INPUT_DAR="$(getInputDar "$FILE_NAME")"
  local INPUT_WIDTH="$(getInputWidth "$FILE_NAME")"
  local INPUT_HEIGHT="$(getInputHeight "$FILE_NAME")"
  local CROP_VALUE="$(getCropValue "$FILE_NAME")"
  local IS_INPUT_PROGRESSIVE="$(isInputProgressive "$FILE_NAME")"
  local DENOISE_VIDEO="$(getDenoise)"
  local INPUT_PIX_FMT="$(getInputPixFmt "$FILE_NAME")"
  local PRESET_GROUP="$(getPresetGroup)"
  local INPUT_COLOR_PRIMITIVES="$(getInputColorPrimitives "$FILE_NAME")"
  local INPUT_FPS="$(getInputFps "$FILE_NAME")"
  local FORCE_8_BIT="$(getForce8bit)"
  local OUTPUT_SCALING_ALGO=""
  local CROP_WIDTH="0"
  local CROP_HEIGHT="0"
  local VIDEO_FILTER=""

  if [ "${PRESET_GROUP}" == "1" ]; then
    OUTPUT_SCALING_ALGO="bicubic"
  else
    OUTPUT_SCALING_ALGO="spline"
  fi

  # Calculate the crop width
  # everything after the first = is considered the crop width
  CROP_WIDTH="${CROP_VALUE#*=}"
  # everything before the first : is considered the crop width
  CROP_WIDTH="${CROP_WIDTH%%:*}"

  # Calculate the crop height
  # everything after the first : is considered the crop height
  CROP_HEIGHT="${CROP_VALUE#*:}"
  # everything before the first : is considered the crop height
  CROP_HEIGHT="${CROP_HEIGHT%%:*}"

  # Construct Video Filter
  if [ "${IS_INPUT_PROGRESSIVE}" == "false" ]; then
    # VIDEO_FILTER="${VIDEO_FILTER}yadif,"
    # http://macilatthefront.blogspot.com/2017/04/deinterlacing-hd-footage-without-losing.html
    VIDEO_FILTER="${VIDEO_FILTER}bwdif,"
    # http://wp.xin.at/archives/5287
    # VIDEO_FILTER="${VIDEO_FILTER}nnedi=weights=nnedi3_weights.bin:field='tf':nsize='s48x6':nns='n256':pscrn='new',"
  fi
  # Crop Video. No need to wast resolution here when PLEX lets us use anamorphic scaling in 720p.
  if [ "${CROP_VALUE}" != "crop=${INPUT_WIDTH}:${INPUT_HEIGHT}:0:0" ]; then
    VIDEO_FILTER="${VIDEO_FILTER}${CROP_VALUE},"
  fi
  if [ "${PRESET_GROUP}" != "1" ] && [ "${CROP_HEIGHT}" -lt "376" ] && [ "${CROP_HEIGHT}" -gt "360" ]; then
    CROP_HEIGHT="360"
    VIDEO_FILTER="${VIDEO_FILTER}crop=${CROP_WIDTH}:360,"
  fi
  # Denoise Video. Pixel format should end up in yuv420p10le.
  if [ "${DENOISE_VIDEO}" == "false" ]; then
    if [ "${INPUT_PIX_FMT}" != "yuv420p10le" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}format=yuv420p10le,"
    fi
  elif [ "${PRESET_GROUP}" == "1" ]; then
    VIDEO_FILTER="${VIDEO_FILTER}hqdn3d=2:2:9:9,"
    if [ "${INPUT_PIX_FMT}" != "yuv420p10le" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}format=yuv420p10le,"
    fi
  elif [ "${INPUT_PIX_FMT}" != "yuv420p" ]; then
    VIDEO_FILTER="${VIDEO_FILTER}format=yuv420p,nlmeans='1.0:7:5:3:3',format=yuv420p10le,"
  else
    VIDEO_FILTER="${VIDEO_FILTER}nlmeans='1.0:7:5:3:3',format=yuv420p10le,"
  fi
  # Migrate Video to 720p colorspace. Not doing so will cause playback issues on some players.
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
  # Double resolution when necessary
  # Only use nural network AI super-resolution when preset is not: ultrafast, superfast, veryfast, faster
  local SCALE_WIDTH="false"
  local SCALE_HEIGHT="false"
  if [ "${INPUT_DAR}" -gt "1777" ]; then
    if [ "${CROP_WIDTH}" -lt "1180" ]; then
      SCALE_WIDTH="true"
    fi
    if [ "${CROP_HEIGHT}" -lt "500" ]; then
      SCALE_HEIGHT="true"
    fi
  else
    if [ "${CROP_WIDTH}" -lt "900" ]; then
      SCALE_WIDTH="true"
    fi
    if [ "${CROP_HEIGHT}" -lt "620" ]; then
      SCALE_HEIGHT="true"
    fi
  fi
  if [ "${PRESET_GROUP}" != "1" ]; then
    if [ "${SCALE_WIDTH}" == "true" ] && [ "${SCALE_HEIGHT}" == "true" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih*2:flags=print_info+${OUTPUT_SCALING_ALGO}+full_chroma_inp+full_chroma_int,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${SCALE_WIDTH}" == "true" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw*2:h=ih:flags=print_info+${OUTPUT_SCALING_ALGO}+full_chroma_inp+full_chroma_int,transpose=1,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',transpose=2,"
    elif [ "${SCALE_HEIGHT}" == "true" ]; then
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=iw:h=ih*2:flags=print_info+${OUTPUT_SCALING_ALGO}+full_chroma_inp+full_chroma_int,nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af',"
    fi
  fi
  # Scale Video to 720p resolution.
  if [ "${FORCE_720P}" == "true" ]; then
    if [ "${SCALE_WIDTH}" == "true" ] || [ "${SCALE_HEIGHT}" == "true" ] || [ "${CROP_WIDTH}" -gt "1280" ] || [ "${CROP_HEIGHT}" -gt "720" ]; then
      local OUTPUT_WIDTH="0"
      local OUTPUT_HEIGHT="0"
      if [ "${CROP_WIDTH}" -gt "1280" ]; then
        OUTPUT_WIDTH="1280"
      elif [ "${SCALE_WIDTH}" == "true" ]; then
        if [ "${CROP_WIDTH}" -gt "640" ]; then
          OUTPUT_WIDTH="1280"
        elif [ "${CROP_WIDTH}" -lt "590" ]; then
          OUTPUT_WIDTH="1180"
        else
          OUTPUT_WIDTH=$(echo "2*${CROP_WIDTH}" | bc)
        fi
      else
        OUTPUT_WIDTH="${CROP_WIDTH}"
      fi
      if [ "${CROP_HEIGHT}" -gt "720" ]; then
        OUTPUT_HEIGHT="720"
      elif [ "${SCALE_HEIGHT}" == "true" ]; then
        if [ "${CROP_HEIGHT}" -gt "360" ]; then
          OUTPUT_HEIGHT="720"
        elif [ "${CROP_HEIGHT}" -lt "310" ]; then
          OUTPUT_HEIGHT="620"
        else
          OUTPUT_HEIGHT=$(echo "2*${CROP_HEIGHT}" | bc)
        fi
      else
        OUTPUT_HEIGHT="${CROP_HEIGHT}"
      fi
      VIDEO_FILTER="${VIDEO_FILTER}scale=w=${OUTPUT_WIDTH}:h=${OUTPUT_HEIGHT}:flags=print_info+${OUTPUT_SCALING_ALGO}+full_chroma_inp+full_chroma_int,"
    fi
  fi
  # Convert back to 8bit only when forced to.
  if [ "${FORCE_8_BIT}" == "true" ]; then
    VIDEO_FILTER="${VIDEO_FILTER}format=yuv420p,"
  fi
  # Lightly run denoising to clean up any jitters created by scaling.
  VIDEO_FILTER="${VIDEO_FILTER}hqdn3d=0:0:7:7"
  echo "${VIDEO_FILTER}"
}
optimize () {
  local INPUT_DIR="$(getInputDir)"
  local TITLE="$(getTitle)"
  local INPUT_BITRATE="$(getInputBitrate "$filename")"
  local VIDEO_BITRATE="$(getVideoBitrate)"
  local INPUT_DAR="$(getInputDar "$filename")"
  local INPUT_WIDTH="$(getInputWidth "$filename")"
  local INPUT_HEIGHT="$(getInputHeight "$filename")"
  local IS_OPTIMIZED="true"
  if [ "${INPUT_BITRATE}" -lt "500000" ] || [ "${INPUT_BITRATE}" -gt "${VIDEO_BITRATE}000" ]; then
    IS_OPTIMIZED="false"
  elif [ "${INPUT_WIDTH}" -gt "1280" ] || [ "${INPUT_HEIGHT}" -gt "720" ]; then
    IS_OPTIMIZED="false"
  elif [ "${INPUT_DAR}" -gt "1777" ] && [ "${INPUT_WIDTH}" -lt "1180" ]; then
    IS_OPTIMIZED="false"
  elif [ "${INPUT_DAR}" -lt "1778" ] && [ "${INPUT_HEIGHT}" -lt "620" ]; then
    IS_OPTIMIZED="false"
  fi
  if [ "${IS_OPTIMIZED}" == "true" ]; then
    echo -e "${SUCCESS_FONT}### ${TITLE}.mp4 has already been optimized.${RESET_FONT}"
    downsample "${INPUT_DIR}/${TITLE}/${TITLE}.mp4"
  else
    echo -e "${ALERT_FONT}### Optimizing ${TITLE}.mp4${RESET_FONT}"
    local INPUT_DIR="$(getInputDir)"
    local PRESET="$(getPreset)"
    local PRESET_GROUP="$(getPresetGroup)"
    local INPUT_FPS="$(getInputFps "$filename")"
    local VIDEO_CODEC_LIB="$(getVideoCodecLib)"
    local VIDEO_BUFFER_BITRATE="$(getVideoBufferBitrate)"
    local VIDEO_PROFILE="$(getVideoProfile)"
    local FORCE_AVC="$(getForceAvc)"
    local INPUT_AUDIO_CHANNELS="$(getInputAudioChannels)"
    local CRF=""
    local VIDEO_FILTER="$(getVideoFilter "true" "$filename")"

    # Calculate CRF
    if [ "${PRESET_GROUP}" == "1" ]; then
      CRF="20"
    elif [ "${PRESET_GROUP}" == "2" ]; then
      CRF="16"
    else
      CRF="10"
    fi

    echo -e "${INFO_FONT}### Video Filter: $VIDEO_FILTER${RESET_FONT}"
    if [ "$(getDryRun)" == "false" ]; then
      initTmpDirs
      local TMP_DIR="$(getTmpDir)"
      local TMP_FILENAME="$(getTmpDir)/original.mp4"
      cp "${filename}" "${TMP_FILENAME}"
      # Set FFMPEG Parameters
      local FFMPEG_PARAMS=()
      FFMPEG_PARAMS+=(-i "${TMP_FILENAME}")
      FFMPEG_PARAMS+=(-map "0:v:0")
      FFMPEG_PARAMS+=(-vf "${VIDEO_FILTER}")
      FFMPEG_PARAMS+=(-vsync 1)
      FFMPEG_PARAMS+=(-vcodec "${VIDEO_CODEC_LIB}")
      FFMPEG_PARAMS+=(-r "${INPUT_FPS}")
      FFMPEG_PARAMS+=(-crf "${CRF}")
      FFMPEG_PARAMS+=(-maxrate "${VIDEO_BITRATE}k")
      FFMPEG_PARAMS+=(-bufsize "${VIDEO_BUFFER_BITRATE}k")
      FFMPEG_PARAMS+=(-preset "${PRESET}")
      FFMPEG_PARAMS+=(-profile:v "${VIDEO_PROFILE}")
      if [ "${FORCE_AVC}" == "true" ]; then
        FFMPEG_PARAMS+=(-level:v 4.0)
        FFMPEG_PARAMS+=(-g 60)
        FFMPEG_PARAMS+=(-sc_threshold 0)
      else
        FFMPEG_PARAMS+=(-x265-params "level-idc=40:keyint=60:min-keyint=60:scenecut=0")
      fi
      FFMPEG_PARAMS+=(-map "0:a:0")
      FFMPEG_PARAMS+=(-c:a aac)
      FFMPEG_PARAMS+=(-filter:a "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
      if [ "${INPUT_AUDIO_CHANNELS}" == "1" ] || [ "${INPUT_AUDIO_CHANNELS}" == "2" ]; then
        FFMPEG_PARAMS+=(-ab "192k")
        FFMPEG_PARAMS+=(-ac 2)
      else
        FFMPEG_PARAMS+=(-ab "448k")
        FFMPEG_PARAMS+=(-ac "${INPUT_AUDIO_CHANNELS}")
      fi
      FFMPEG_PARAMS+=(-ar 44100)
      FFMPEG_PARAMS+=(-movflags +faststart)
      FFMPEG_PARAMS+=(-f "mp4")
      FFMPEG_PARAMS+=(-y)
      FFMPEG_PARAMS+=("${TMP_DIR}/optimized.mp4")
#      echo "FFMPEG_PARAMS: ${FFMPEG_PARAMS}"
      if ffmpeg ${FFMPEG_PARAMS[@]}; then
        mkdir -p "$(getInputDir)$(getTitle)/orig"
        mv "$filename" "${INPUT_DIR}/${TITLE}/orig/${TITLE}.mp4"
        cp "${TMP_DIR}/optimized.mp4" "${INPUT_DIR}/${TITLE}/${TITLE}.mp4"
        if [ "$(getDiscardOriginal)" == "true" ]; then
          rm -rf "${INPUT_DIR}/${TITLE}/orig"
        fi
        rm -rf "${TMP_DIR}"
        downsample "${INPUT_DIR}/${TITLE}/${TITLE}.mp4"
      fi
    fi
  fi
}
downsample () {
  local FILENAME="${1}"
  local INPUT_DIR="$(getInputDir)"
  local INPUT_TITLE="$(getTitle)"
  if [ -f "${INPUT_DIR}/${INPUT_TITLE}/${INPUT_TITLE} - 48k audio.mp4" ]; then
    echo -e "${SUCCESS_FONT}### ${INPUT_TITLE}.mp4 audio has already been downsampled.${RESET_FONT}"
  else
    echo -e "${ALERT_FONT}### Downsample ${INPUT_TITLE}.mp4 audio to 48k.${RESET_FONT}"
    local IS_FDK_AAC_INSTALLED="$(isFdkAacInstalled)"
    if [ "${IS_FDK_AAC_INSTALLED}" == "false" ]; then
      echo -e "${INFO_FONT}### AAC HE V2 is not installed, falling back to AAC Mono for 48k audio version.${RESET_FONT}"
      echo -e "${INFO_FONT}###   To install AAC HE V2 on MacOS:${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew uninstall ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew tap homebrew-ffmpeg/ffmpeg${RESET_FONT}"
      echo -e "${INFO_FONT}###     brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-fdk-aac --HEAD${RESET_FONT}"
    fi
    if [ "$(getDryRun)" == "false" ]; then
      initTmpDirs
      local TMP_DIR="$(getTmpDir)"
      local TMP_FILENAME="$(getTmpDir)/original.mp4"
      cp "${FILENAME}" "${TMP_FILENAME}"
      local FFMPEG_DOWNSAMPLE_PARAMS=()
      FFMPEG_DOWNSAMPLE_PARAMS+=(-i "${TMP_FILENAME}")
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
      FFMPEG_DOWNSAMPLE_PARAMS+=(-y)
      FFMPEG_DOWNSAMPLE_PARAMS+=("${TMP_DIR}/downsample.mp4")
      if ffmpeg ${FFMPEG_DOWNSAMPLE_PARAMS[@]}; then
        cp "${TMP_DIR}/downsample.mp4" "${INPUT_DIR}/${INPUT_TITLE}/${INPUT_TITLE} - 48k audio.mp4"
        rm -rf "${TMP_DIR}"
      fi
      rm -rf "${TMP_DIR}"
    fi
  fi
}
concat_optimize() {
  local INPUT_FILE_NAME="${1}"
  local INPUT_WIDTH="$(getInputWidth "${INPUT_FILE_NAME}")"
  local INPUT_HEIGHT="$(getInputHeight "${INPUT_FILE_NAME}")"
  if [ "${INPUT_WIDTH}" -gt "959" ] && [ "${INPUT_HEIGHT}" -gt "547" ]; then
    echo -e "${SUCCESS_FONT}### ${INPUT_FILE_NAME} has already been optimized.${RESET_FONT}"
  else
    local PRESET="$(getPreset)"
    local PRESET_GROUP="$(getPresetGroup)"
    local INPUT_FPS="$(getInputFps "${INPUT_FILE_NAME}")"
    local VIDEO_FILTER=""
    local CRF=""

    # Calculate Video Filter
    if [ "${PRESET_GROUP}" == "1" ]; then
      VIDEO_FILTER="$(getVideoFilter "true" "${INPUT_FILE_NAME}")"
    else
      VIDEO_FILTER="$(getVideoFilter "false" "${INPUT_FILE_NAME}")"
    fi

    # Calculate CRF
    if [ "${PRESET_GROUP}" == "1" ]; then
      CRF="20"
    elif [ "${PRESET_GROUP}" == "2" ]; then
      CRF="10"
    else
      CRF="6"
    fi

    echo -e "${ALERT_FONT}### Optimizing ${INPUT_FILE_NAME}${RESET_FONT}"
    echo -e "${INFO_FONT}### Video Filter: $VIDEO_FILTER${RESET_FONT}"
    if [ "$(getDryRun)" == "false" ]; then
      initTmpDirs
      local TMP_DIR="$(getTmpDir)"
      local TMP_FILENAME="$(getTmpDir)/original.mp4"
      cp "${INPUT_FILE_NAME}" "${TMP_FILENAME}"
      # Set FFMPEG Parameters
      local FFMPEG_PARAMS=()
      FFMPEG_PARAMS+=(-i "${TMP_FILENAME}")
      FFMPEG_PARAMS+=(-map "0:v:0")
      FFMPEG_PARAMS+=(-vf "${VIDEO_FILTER}")
      FFMPEG_PARAMS+=(-vsync 1)
      FFMPEG_PARAMS+=(-vcodec "libx264")
      FFMPEG_PARAMS+=(-r "${INPUT_FPS}")
      FFMPEG_PARAMS+=(-crf "${CRF}")
      FFMPEG_PARAMS+=(-preset "${PRESET}")
      FFMPEG_PARAMS+=(-profile:v "high10")
      FFMPEG_PARAMS+=(-level:v 6.1)
      FFMPEG_PARAMS+=(-g 60)
      FFMPEG_PARAMS+=(-sc_threshold 0)
      FFMPEG_PARAMS+=(-map "0:a:0")
      FFMPEG_PARAMS+=(-c:a copy)
      FFMPEG_PARAMS+=(-movflags +faststart)
      FFMPEG_PARAMS+=(-f "mp4")
      FFMPEG_PARAMS+=(-y)
      FFMPEG_PARAMS+=("${TMP_DIR}/optimized.mp4")
      if ffmpeg ${FFMPEG_PARAMS[@]}; then
        mv "${INPUT_FILE_NAME}" "${INPUT_FILE_NAME}.orig"
        cp "${TMP_DIR}/optimized.mp4" "${INPUT_FILE_NAME}"
        if [ "$(getDiscardOriginal)" == "true" ]; then
          rm "${INPUT_FILE_NAME}.orig"
        fi
        rm -rf "${TMP_DIR}"
      fi
    fi
  fi
}
concat () {
  local i="0"
  while [ "${i}" -lt "9000" ]; do
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mp4" ]; then
      concat_optimize "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mp4"
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.m4v" ]; then
      concat_optimize "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.m4v"
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mkv" ]; then
      concat_optimize "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.mkv"
    fi
    if [ -f "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.webm" ]; then
      concat_optimize "$(getInputDir)$(getTitle)/$(getTitle) - pt${i}.webm"
    fi
    i=$(( $i + 1 ))
  done
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
  local MAX_INPUT_WIDTH="0"
  local MAX_INPUT_HEIGHT="0"
  local MAX_INPUT_DAR="0"
  for origPart in "$(getTmpDir)"/*.m4v; do
    local INPUT_AUDIO_CHANNELS=$((ffprobe -v error -select_streams a:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=channels "${origPart}") 2>&1)
    local INPUT_WIDTH="$(getInputWidth "$origPart")"
    local INPUT_HEIGHT="$(getInputHeight "$origPart")"
    local INPUT_DAR="$(getInputDar "$origPart")"
    if [ "${INPUT_WIDTH}" -gt "${MAX_INPUT_WIDTH}" ]; then
      MAX_INPUT_WIDTH="${INPUT_WIDTH}"
    fi
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

  # When the DAR s larger than 16:9 then the width fills the frame and the height should be proportional.
  # Otherwise the height fills the frame and the width should be proportional.
  local MAX_OUTPUT_WIDTH="0"
  local MAX_OUTPUT_HEIGHT="0"
  if [ "${MAX_INPUT_HEIGHT}" -gt "${MAX_OUTPUT_HEIGHT}" ]; then
    MAX_OUTPUT_HEIGHT="${MAX_INPUT_HEIGHT}"
  fi
  MAX_OUTPUT_WIDTH=$(echo "${MAX_INPUT_DAR}*${MAX_OUTPUT_HEIGHT}/1000" | bc)
  # for each video, lets do some processing and then scale it to fit in the MAX_INPUT_WIDTH by MAX_INPUT_HEIGHT box.
  for origPart in "$(getTmpDir)"/*.m4v; do
    local INPUT_WIDTH=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "${origPart}") 2>&1)
    local INPUT_HEIGHT=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "${origPart}") 2>&1)
    local INPUT_PIX_FMT=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=pix_fmt "${origPart}") 2>&1)
    local INPUT_COLOR_PRIMITIVES=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=color_primaries "${origPart}") 2>&1)
    local CRF=""

    # Calculate CRF
    if [ "${PRESET_GROUP}" == "1" ]; then
      CRF="20"
    elif [ "${PRESET_GROUP}" == "2" ]; then
      CRF="10"
    else
      CRF="6"
    fi

    local ffmpegParams=()
    ffmpegParams+=(-i "${origPart}")
    if [ "$(getProduceSample)" == "true" ]; then
      ffmpegParams+=(-ss "00:00:00")
      ffmpegParams+=(-to "00:00:30")
    fi
    ffmpegParams+=(-map "0:v:0")
    ffmpegParams+=(-map "-0:t") # remove attachments
    local videoFilter=""
    videoFilter="${videoFilter}scale=(iw*sar)*min(${MAX_OUTPUT_WIDTH}/(iw*sar)\,${MAX_OUTPUT_HEIGHT}/ih):ih*min(${MAX_OUTPUT_WIDTH}/(iw*sar)\,${MAX_OUTPUT_HEIGHT}/ih):flags=print_info+spline+full_chroma_inp+full_chroma_int,"
    videoFilter="${videoFilter}pad=${MAX_OUTPUT_WIDTH}:${MAX_OUTPUT_HEIGHT}:(${MAX_OUTPUT_WIDTH}-iw*min(${MAX_OUTPUT_WIDTH}/iw\,${MAX_OUTPUT_HEIGHT}/ih))/2:(${MAX_OUTPUT_WIDTH}-ih*min(${MAX_OUTPUT_WIDTH}/iw\,${MAX_OUTPUT_HEIGHT}/ih))/2"
    echo -e "${INFO_FONT}### Video Filter: $videoFilter${RESET_FONT}"
    ffmpegParams+=(-vf "${videoFilter}")
    ffmpegParams+=(-vsync 1)
    ffmpegParams+=(-vcodec "libx264")
    ffmpegParams+=(-r "${INPUT_FPS}")
    ffmpegParams+=(-crf "${CRF}")
    ffmpegParams+=(-preset "$(getPreset)")
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
  local MOVIE_LIST_FILE="$(getTmpDir)/mylist.txt"
  local METADATA_FILE="$(getTmpDir)/metadata.txt"
  echo ";FFMETADATA1" > "$METADATA_FILE"
  echo "" >> "$METADATA_FILE"
  # initialize chapter count
  local CHAPTER="1"
  # initialize the chapter start time in milliseconds
  local START="0"
  # initialize the chapter end time in milliseconds
  local END="0"
  for f in "$(getTmpDir)"/*.mp4; do
    # get the duration in milliseconds from the video
    local DURATION="$(getDuration "$f")"
    local CHAPTER_TITLE="CHAPTER ${CHAPTER}"
    local METADATA_TITLE="$(getMetadataTitle "$f")"
    if [ "${METADATA_TITLE}" != "" ]; then
      CHAPTER_TITLE="${CHAPTER_TITLE}: ${METADATA_TITLE}"
    fi
    END=$(( $START + $DURATION ))
    # write chapter's metadata to the video's temp metadata file
    echo "[CHAPTER]" >> "${METADATA_FILE}"
    echo "TIMEBASE=1/1000" >> "${METADATA_FILE}"
    echo "START=${START}" >> "${METADATA_FILE}"
    echo "END=${END}" >> "${METADATA_FILE}"
    echo "title=${CHAPTER_TITLE}" >> "${METADATA_FILE}"
    echo "" >> "${METADATA_FILE}"
    # set next chapter's start time to this chapter's end time
    START=$END
    CHAPTER=$(( $CHAPTER + 1 ))
    echo "file '$f'" >> "${MOVIE_LIST_FILE}"
  done
  ffmpeg -f concat -safe 0 -i "${MOVIE_LIST_FILE}" -i "${METADATA_FILE}" -map_metadata 1 -c copy "$(getInputDir)$(getTitle)/$(getTitle).mp4"
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
# returns the preset to use. Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow, placebo
getPreset() {
  echo $preset
}
getPresetGroup() {
  if [ "$preset" == "ultrafast" ] || [ "$preset" == "superfast" ] || [ "$preset" == "veryfast" ] || [ "$preset" == "faster" ]; then
    echo "1"
  elif [ "$preset" == "slower" ] || [ "$preset" == "veryslow" ] || [ "$preset" == "placebo" ]; then
    echo "3"
  else
    echo "2"
  fi
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
        local width=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=width "${1}") 2>&1)
        echo $width
}
# get the input file's height
getInputHeight () {
        local height=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=height "${1}") 2>&1)
        echo $height
}
getInputPixFmt () {
        local pixFmt=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=pix_fmt "${1}") 2>&1)
        echo $pixFmt
}
getInputColorPrimitives() {
        local colorPrimitives=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=color_primaries "${1}") 2>&1)
        echo $colorPrimitives
}
getInputBitrate() {
  local bitrate=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=bit_rate "${1}") 2>&1)
  if [ "${bitrate}" == "N/A" ]; then
    echo "-1"
  else
    echo $bitrate
  fi
}
# get the input file's DAR
getInputDar () {
    local INPUT_DAR=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=display_aspect_ratio "${1}") 2>&1)
    # everything before the last : is considered the DAR's width
    local INPUT_DAR_WIDTH="${INPUT_DAR%:*}"
    # everything after the last :  is considered the DAR's height
    local INPUT_DAR_HEIGHT=${INPUT_DAR##*:}
    INPUT_DAR=$(echo "1000*${INPUT_DAR_WIDTH}/${INPUT_DAR_HEIGHT}" | bc)
    echo "${INPUT_DAR}"
}
getCropValue() {
  local CROP_VALUE=$(ffmpeg -t 1000 -i "${1}" -vf "select=not(mod(n\,1000)),cropdetect=36:1:0" -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1)
  echo $CROP_VALUE
}
getDuration() {
  # get the duration in milliseconds from the video
  local DURATION=`ffmpeg -i "${1}" 2>&1 | awk '$1 ~ /^Duration/' | cut -d ' ' -f 4 | sed s/,// | awk '{ split($1, A, ":"); print 3600000*A[1] + 60000*A[2] + 1000*A[3] }'`   
  echo $DURATION
}
getMetadataTitle() {
  local TITLE=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries format_tags=title "${1}") 2>&1)
  echo $TITLE
}
# get the input file's FPS
getInputFps () {
        local fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "${1}") 2>&1)
        fps=$(echo "10*$fps" | bc)
        local avg_fps=$((ffprobe -v error -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 -show_entries stream=avg_frame_rate "${1}") 2>&1)
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
# returns true when the input video is progressive, otherwise returns false
# untested
isInputProgressive() {
  local IDET=$(ffmpeg -i "${1}" -vf "idet" -f null - 2>&1 | tail -1)
  local TFF="${IDET##*TFF:}"
  TFF="${TFF%BFF:*}"
  TFF=$(echo "$TFF" | bc)
  local BFF="${IDET##*BFF:}"
  BFF="${BFF%Progressive:*}"
  BFF=$(echo "$BFF" | bc)
  local PROGRESSIVE="${IDET##*Progressive:}"
  PROGRESSIVE="${PROGRESSIVE%Undetermined:*}"
  PROGRESSIVE=$(echo "$PROGRESSIVE" | bc)
  local INTERLACE=$(echo "$TFF+$BFF" | bc)
  if [ "${PROGRESSIVE}" -gt "${INTERLACE}" ]; then
    echo "true"
  else
    echo "false"
  fi
}
isFdkAacInstalled () {
  local FFMPEG_VERSION=$((ffmpeg -version) 2>&1)
  if [[ "${FFMPEG_VERSION}" == *"--enable-libfdk-aac"* ]]; then
    echo "true"
  else
    echo "false"
  fi
}
isLibVidStabInstalled () {
  local FFMPEG_VERSION=$((ffmpeg -version) 2>&1)
  if [[ "${FFMPEG_VERSION}" == *"--enable-libvidstab"* ]]; then
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
