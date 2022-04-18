package main

import (
    "os"
    "fmt"
    "strings"
)

type Media struct {
    name     string
    path     string
    video    *Video
    audio    *Audio
}

func GetMedia(path string, title string) *Media {
    if !strings.HasSuffix(path, "/") {
        path = path + "/"
    }
    dirInfo, err := os.Stat(path + title)
    if err != nil || !dirInfo.IsDir() {
        return nil
    }
    for _, extension := range VideoExtensions {
        absolute := path + title + "/" + title + "." + extension
        if _, err := os.Stat(absolute); err == nil {
            m := Media{}
            m.name = title
            m.path = path + title + "/"
            m.video = &Video{}
            m.video.path = absolute
            return &m
        }
    }
    return nil
}

func (m *Media) Name() string {
    return m.name
}

func (m *Media) Path() string {
    return m.path
}

func (m *Media) Video() *Video {
    return m.video
}

func (m *Media) Audio() *Audio {
    if m.audio != nil {
        return m.audio
    }
    m.audio = &Audio{}
    m.audio.path = m.video.path
    return m.audio
}

func (m *Media) MaxAudioBitrate() int {
    return 90000 + (m.Audio().Channels() - 1) * 12000
}

func (m *Media) MaxVideoBitrate() int {
    return GetParameters().Bitrate() - m.MaxAudioBitrate()
}

func (m *Media) OptimizedAudio() bool {
    if m.Audio().Bitrate() < 10000 {
        return false
    }
    if m.Audio().Bitrate() > m.MaxAudioBitrate() {
        return false
    }
    return true
}

func (m *Media) OptimizedVideo() bool {
    if m.Video().Bitrate() < 500000 {
        return false
    }
    if m.Video().Bitrate() + m.Audio().Bitrate() > GetParameters().Bitrate() {
        return false
    }
    if m.Video().Width() > 1280 || m.Video().Height() > 720 {
        return false
    }
    if m.Video().Dar() > float64(1.777) && m.Video().Width() < 1180 {
        return false
    }
    if m.Video().Dar() < float64(1.778) && m.Video().Height() < 620 {
        return false
    }
    return true
}

// Source is optimized when video is optimized and video bitrate plus audio bitrate is less than the target bitrate.
func (m *Media) Optimized() bool {
    return m.OptimizedVideo() && m.Video().Bitrate() + m.Audio().Bitrate() < GetParameters().Bitrate()
}

func (m *Media) Println() {
    fmt.Println("* Media", m.name)
    fmt.Println("  - name:", m.name)
    fmt.Println("  - path:", m.path)
    fmt.Println("  - optimized:", m.Optimized())
    fmt.Println("  * Video")
    fmt.Println("    - width:", m.Video().Width())
    fmt.Println("    - height:", m.Video().Height())
    fmt.Println("    - pix fmt:", m.Video().PixFmt())
    fmt.Println("    - color primaries:", m.Video().ColorPrimaries())
    fmt.Println("    - bitrate:", m.Video().Bitrate())
    fmt.Println("    - dar:", m.Video().Dar())
    fmt.Println("    - sar:", m.Video().Sar())
    fmt.Println("    * Crop")
    fmt.Println("      - filter:", m.Video().Crop().Filter())
    fmt.Println("      - width:", m.Video().Crop().Width())
    fmt.Println("      - height:", m.Video().Crop().Height())
    fmt.Println("    - duration:", m.Video().Duration())
    fmt.Println("    - fps:", m.Video().Fps())
//        fmt.Println("    - progressive:", m.Video().Progressive())
    fmt.Println("  * Audio")
    fmt.Println("    - channels:", m.Audio().Channels())
    fmt.Println("    - bitrate:", m.Audio().Bitrate())    
}
