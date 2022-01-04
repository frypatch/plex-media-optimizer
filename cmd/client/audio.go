package main

import (
    "os/exec"
    "strings"
    "strconv"
)

type Audio struct {
	path     string
    channels *int
    bitrate  *int
}

func (a *Audio) SetPath(path string) {
	a.path = path
}

func (a *Audio) Channels() int {
	if a.channels != nil {
		return *a.channels
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "a:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=channels",
		a.path)
    stdout, _ := cmd.Output()
    channels, _ := strconv.Atoi(strings.TrimSuffix(string(stdout), "\n"))
    a.channels = &channels
    return *a.channels
}

func (a *Audio) Bitrate() int {
	if a.bitrate != nil {
		return *a.bitrate
	}
	cmd := exec.Command(
		"ffprobe",
		"-v", "error",
		"-select_streams", "a:0",
		"-of", "default=noprint_wrappers=1:nokey=1",
		"-show_entries", "stream=bit_rate",
		a.path)
    stdout, _ := cmd.Output()
    bitrateStr := strings.TrimSuffix(string(stdout), "\n")
    if bitrateStr == "" || bitrateStr == "N/A" {
    	bitrate := -1
    	a.bitrate = &bitrate
    	return *a.bitrate
    }
    bitrate, _ := strconv.Atoi(bitrateStr)
    a.bitrate = &bitrate
    return *a.bitrate
}
