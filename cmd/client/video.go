package main

import (
    "fmt"
    "os/exec"
    "strings"
    "strconv"
)

type Video struct {
	name           string
	path           string
    width          *int
    height         *int
    pixFmt         string
    bitrate        *int
    colorPrimaries string
    dar            *float64
    sar            *float64
    crop           *Crop
    duration       *int
    fps            string
    progressive    *bool
}

func (v *Video) Name() string {
	return v.name
}

func (v *Video) Path() string {
	return v.path
}

func (v *Video) SetPath(path string) {
	v.path = path
}

func (v *Video) Width() int {
	if v.width != nil {
		return *v.width
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=width",
		v.path)
    stdout, _ := cmd.Output()
    width, _ := strconv.Atoi(strings.TrimSuffix(string(stdout), "\n"))
    v.width = &width
    return *v.width
}

func (v *Video) Height() int {
	if v.height != nil {
		return *v.height
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=height",
		v.path)
    stdout, _ := cmd.Output()
    height, _ := strconv.Atoi(strings.TrimSuffix(string(stdout), "\n"))
    v.height = &height
    return *v.height
}

func (v *Video) PixFmt() string {
	if v.pixFmt != "" {
		return v.pixFmt
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=pix_fmt",
		v.path)
    stdout, _ := cmd.Output()
    v.pixFmt = strings.TrimSuffix(string(stdout), "\n")
    return v.pixFmt
}

func (v *Video) ColorPrimaries() string {
	if v.colorPrimaries != "" {
		return v.colorPrimaries
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=color_primaries",
		v.path)
    stdout, _ := cmd.Output()
    v.colorPrimaries = strings.TrimSuffix(string(stdout), "\n")
    return v.colorPrimaries
}

func (v *Video) Bitrate() int {
	if v.bitrate != nil {
		return *v.bitrate
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=bit_rate",
		v.path)
    stdout, _ := cmd.Output()
    bitrateStr := strings.TrimSuffix(string(stdout), "\n")
    if bitrateStr == "" || bitrateStr == "N/A" {
    	bitrate := -1
    	v.bitrate = &bitrate
    	return *v.bitrate
    }
    bitrate, _ := strconv.Atoi(bitrateStr)
    v.bitrate = &bitrate
    return *v.bitrate
}

func (v *Video) Dar() float64 {
	if v.dar != nil {
		return *v.dar
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=display_aspect_ratio",
		v.path)
    stdout, _ := cmd.Output()
    darRatio := strings.TrimSuffix(string(stdout), "\n")
    left, _ := strconv.ParseFloat(strings.Split(darRatio, ":")[0], 64)
    right, _ := strconv.ParseFloat(strings.Split(darRatio, ":")[1], 64)
    dar := left/right
    v.dar = &dar
    return *v.dar
}

func (v *Video) Sar() float64 {
	if v.sar != nil {
		return *v.sar
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=sample_aspect_ratio",
		v.path)
    stdout, _ := cmd.Output()
    sarRatio := strings.TrimSuffix(string(stdout), "\n")
    left, _ := strconv.ParseFloat(strings.Split(sarRatio, ":")[0], 64)
    right, _ := strconv.ParseFloat(strings.Split(sarRatio, ":")[1], 64)
    sar := left/right
    v.sar = &sar
    return *v.sar
}

func (v *Video) Crop() *Crop {
	if v.crop != nil {
		return v.crop
	}
	v.crop = &Crop{}
	cmd := `ffmpeg -t 1000 -i "%s" -vf "select=not(mod(n\,1000)),cropdetect=36:1:0" -f null - 2>&1 | awk '/crop/ { print $NF }' | tail -1`
    stdout, _ := exec.Command("bash","-c",fmt.Sprintf(cmd, v.path)).Output()
    v.crop.filter = strings.TrimSuffix(string(stdout), "\n")
	if v.crop.filter != "" {
		return v.crop
	}
	v.crop.filter = fmt.Sprintf("crop=%v:%v:0:0", v.Width(), v.Height())
    return v.crop
}

func (v *Video) Duration() int {
	if v.duration != nil {
		return *v.duration
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "format=duration",
		v.path)
	stdout, _ := cmd.Output()
	seconds, _ := strconv.ParseFloat(strings.TrimSuffix(string(stdout), "\n"), 64)
	duration := int(seconds * 1000)
	v.duration = &duration
	return *v.duration
}

func calcFpsFromAvg(path string) string {
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=avg_frame_rate",
		path)
	stdout, _ := cmd.Output()
    fpsRatio := strings.TrimSuffix(string(stdout), "\n")
    fpsLeft, _ := strconv.Atoi(strings.Split(fpsRatio, "/")[0])
    fpsRight, _ := strconv.Atoi(strings.Split(fpsRatio, "/")[1])
    fps := float64(fpsLeft) / float64(fpsRight)
    if fps < float64(24.3) {
    	return "24000/1001"
    }
    if fps < float64(26) {
    	return "25/1"
    }
    if fps < float64(46) {
    	return "30000/1001"
    }
    if fps < float64(49) {
    	return "24000/1001"
    }
    if fps < float64(51) {
    	return "25/1"
    }
    return "30000/1001"
}

func (v *Video) Fps() string {
	if v.fps != "" {
		return v.fps
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "v:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=r_frame_rate",
		v.path)
	stdout, _ := cmd.Output()
    fpsRatio := strings.TrimSuffix(string(stdout), "\n")
    if fpsRatio == "" || strings.HasSuffix(fpsRatio, "/0") {
		v.fps = calcFpsFromAvg(v.path)
		return v.fps
    }
    fpsLeft, _ := strconv.Atoi(strings.Split(fpsRatio, "/")[0])
    fpsRight, _ := strconv.Atoi(strings.Split(fpsRatio, "/")[1])
    quotient := fpsLeft / fpsRight
    remainder := fpsLeft % fpsRight
    if remainder == 0 && (quotient == 24 || quotient == 48) {
    	v.fps = "24/1"
    	return v.fps
    }
    if remainder == 0 && (quotient == 25 || quotient == 50) {    	
    	v.fps = "25/1"
    	return v.fps
    }
    if remainder == 0 && (quotient == 30 || quotient == 60) {    	
    	v.fps = "30/1"
    	return v.fps
    }
    fps := float64(fpsLeft) / float64(fpsRight)
    if fps < float64(24.3) {
    	v.fps = "24000/1001"
    	return v.fps
    }
    if fps < float64(26) {
    	v.fps = "25/1"
    	return v.fps
    }
    if fps < float64(46) {
    	v.fps = "30000/1001"
    	return v.fps
    }
    if fps < float64(49) {
    	v.fps = "24000/1001"
    	return v.fps
    }
    if fps < float64(51) {
    	v.fps = "25/1"
    	return v.fps
    }
    if fps < float64(62) {
    	v.fps = "30000/1001"
    	return v.fps
    }
	v.fps = calcFpsFromAvg(v.path)
	return v.fps
}

func (v *Video) Progressive() bool {
	if v.progressive != nil {
		return *v.progressive
	}
	cmd := `ffmpeg -i "%s" -vf "idet" -f null - 2>&1 | tail -1`
    stdout, _ := exec.Command("bash","-c",fmt.Sprintf(cmd, v.path)).Output()
    idet := strings.TrimSuffix(string(stdout), "\n")
    tff, _ := strconv.Atoi(strings.TrimSpace(strings.Split(strings.Split(idet, "TFF:")[1],"BFF:")[0]))
    bff, _ := strconv.Atoi(strings.TrimSpace(strings.Split(strings.Split(idet, "BFF:")[1],"Progressive:")[0]))
    pro, _ := strconv.Atoi(strings.TrimSpace(strings.Split(strings.Split(idet, "Progressive:")[1],"Undetermined:")[0]))
    progressive := pro > tff + bff
    v.progressive = &progressive
    return *v.progressive
}

func (v *Video) Filter(force720p bool) string {
    cropWidth := v.Crop().Width()
    cropHeight := v.Crop().Height()
    vf := []string{}
    // If decombing is enabled and the input video has more interlaced frames than progressive frames then lets deinterlace it first.
    // Note: Handbrake's decomb option provides a better result. Use that when possible; this is just here as a fail-safe.
    if !GetParameters().Ultrafast() && GetParameters().Decomb() && !v.Progressive() {
        // https://macilatthefront.blogspot.com/2021/05/which-deinterlacing-algorithm-is-best.html
        vf = append(vf, "bwdif")
    }
    // Crop Video.
    // No need to waist resolution here when PLEX lets us use anamorphic scaling in 720p.
    // Only crop when the input reslution and the crop resolution are dfferent
    if cropWidth != v.Width() && cropHeight != v.Height() {
        vf = append(vf, v.Crop().Filter())
    }
    // If cropped video resolution is close to exactly half the height of 720p then lets crop out the
    //   middle 360 vertical pixels so that we don't end up bluring the vertical resolution to accomidate
    //   a couple of edge pixels that don't really matter.
    if cropHeight < 376 && cropHeight > 360 {
        cropHeight = 360
        vf = append(vf, fmt.Sprintf("crop=%d:360,", cropWidth))
    }
    // Denoise Video when enabled.
    // Only use the better nlmeans denoiser when when preset is not: ultrafast, superfast, veryfast, faster
    // Pixel format should end up in yuv420p10le.
    if GetParameters().Ultrafast() || !GetParameters().Denoise() {
        if v.PixFmt() != "yuv420p10le" {
            vf = append(vf, "format=yuv420p10le")
        }
    } else if GetParameters().PresetGroup() == 0 {
        vf = append(vf, "hqdn3d=2:2:15:15")
        if v.PixFmt() != "yuv420p10le" {
            vf = append(vf, "format=yuv420p10le")
        }
    } else {
        // nlmeans needs the video format to be in yuv420p or it crashes.
        if v.PixFmt() != "yuv420p" {
            vf = append(vf, "format=yuv420p")
        }
        vf = append(vf, "nlmeans='1.0:7:5:3:3'", "format=yuv420p10le")
    }
    // Migrate Video to 720p colorspace. Not doing so will cause playback issues on some players.
    if v.ColorPrimaries() == "unknown" {
        if v.Height() > 720 {
            vf = append(vf, "colorspace=bt709:iall=bt2020:fast=1")
        } else if v.Height() > 480 {
            vf = append(vf, "colorspace=bt709:iall=bt709:fast=1")
        } else if v.Fps() == "25/1" || v.Fps() == "50/1" {
            vf = append(vf, "colorspace=bt709:iall=bt601-6-625:fast=1")
        } else {
            vf = append(vf, "colorspace=bt709:iall=bt601-6-525:fast=1")
        }
    } else if v.ColorPrimaries() != "bt709" {
        vf = append(vf, fmt.Sprintf("colorspace=bt709:iall=%s:fast=1", v.ColorPrimaries()))
    }
    wasScaled := false
    // Determine when non-realtime horizontal and/or vertical scalling would increase quality.
    shouldScaleWidth := false
    shouldScaleHeight := false
    if v.Dar() > float64(1.777) {
        if cropWidth < 1180 {
            shouldScaleWidth = true
        }
        if cropHeight < 500 {
            shouldScaleHeight = true
        }
    } else {
        if cropWidth < 900 {
            shouldScaleWidth = true
        }
        if cropHeight < 620 {
            shouldScaleHeight = true
        }
    }
    // Only use nural network AI super-resolution when preset is not: ultrafast, superfast, veryfast, faster
    if GetParameters().PresetGroup() != 0 {
        if shouldScaleWidth && shouldScaleHeight {
            vf = append(vf, "scale=w=iw*2:h=ih*2:flags=print_info+spline+full_chroma_inp+full_chroma_int")
            wasScaled = true
            vf = append(vf, "nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af'")
            vf = append(vf, "transpose=1")
            vf = append(vf, "nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af'")
            vf = append(vf, "transpose=2")
        } else if shouldScaleWidth {
            vf = append(vf, "scale=w=iw*2:h=ih:flags=print_info+spline+full_chroma_inp+full_chroma_int")
            wasScaled = true
            vf = append(vf, "transpose=1")
            vf = append(vf, "nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af'")
            vf = append(vf, "transpose=2")
        } else if shouldScaleHeight {
            vf = append(vf, "scale=w=iw:h=ih*2:flags=print_info+spline+full_chroma_inp+full_chroma_int")
            wasScaled = true
            vf = append(vf, "nnedi=weights=nnedi3_weights.bin:nsize='s16x6':nns='n64':pscrn='new':field='af'")
        }
    }
    // When true then force the output video to be 720p.
    // This will allow Plex to direct play videos in the 2mbps to 4mbps ranges.
    if force720p {
        if shouldScaleWidth || shouldScaleHeight || cropWidth > 1280 || cropHeight > 720 {
            outputWidth := 0
            outputHeight := 0
            if cropWidth > 1280 {
                outputWidth = 1280
            } else if shouldScaleWidth {
                if cropWidth > 640 {
                    outputWidth = 1280
                } else if outputWidth < 590 {
                    outputWidth = 1180
                } else {
                    outputWidth = 2 * cropWidth
                }
            } else {
                outputWidth = cropWidth
            }
            if cropHeight > 720 {
                outputHeight = 720
            } else if shouldScaleHeight {
                if cropHeight > 360 {
                    outputHeight = 720
                } else if cropHeight < 310 {
                    outputHeight = 620
                } else {
                    outputHeight = 2 * cropHeight
                }
            } else {
                outputHeight = cropHeight
            }
            vf = append(vf, fmt.Sprintf("scale=w=%d:h=%d:flags=print_info+%s+full_chroma_inp+full_chroma_int", outputWidth, outputHeight, GetParameters().ScalingAlgo()))
            wasScaled = true
        }
    }
    // Convert back to 8bit only when forced to.
    if GetParameters().Force8Bit() {
        vf = append(vf, "format=yuv420p")
    }
    // Run a light denoiser and light sharpener to clean up any jitters created by scaling.
    if !GetParameters().Ultrafast() && wasScaled {
        vf = append(vf, "hqdn3d=1:1:9:9")
        vf = append(vf, "unsharp=5:5:0.8:3:3:0.4")
    }
    return strings.Join(vf, ",")
}
