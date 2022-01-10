package main

import (
    "io/ioutil"
    "path/filepath"
    "fmt"
    "os/exec"
    "os"
    "strconv"
)

func Optimize(m *Media) {
    if m.Optimized() {
        fmt.Printf("### %s has already been optimized.\n", m.Name())
        return
    }
    fmt.Printf("### Optimizing %s.\n", m.Name())
    if GetParameters().DryRun() {
        return
    }
    if !m.OptimizedVideo() {
        if (!optimizeVideo(m)) {
            fmt.Println("Failed to optimize video.")
            return
        }
    }
    _, err := os.Stat(m.Path() + "original_audio.mka")
    if err != nil {
        err2 := backupAudio(m)
        if err2 != nil {
            fmt.Printf("Failed to backup audio: %v\n", err2)
            return
        }
    }
    if !m.OptimizedAudio() {
        if (!optimizeAudio(m)) {
            fmt.Println("Failed to optimize audio.")
        }
    }
    GetParameters().Cleanup(m.Path())
}

func backupAudio(m *Media) error {
    fmt.Println("Backup Audio:")
    tmpDir, err := ioutil.TempDir(os.TempDir(), "optimize-")
    defer os.RemoveAll(tmpDir)
    if err != nil {
        return err
    }
    original := filepath.Join(tmpDir, "original.mp4")
    backup := filepath.Join(tmpDir, "backup.mka")
    Copy(m.Video().Path(), original)
    params := []string{}
    params = append(params, "-i", original)
    params = append(params, "-vn")
    params = append(params, "-acodec", "copy")
    params = append(params, "-y")
    params = append(params, backup)
    PrintFfmpeg(params)
    fmt.Println("Executing...")
    err = exec.Command("ffmpeg", params...).Run()
    if err != nil {
        return err
    }
    return Move(backup, m.Path() + "original_audio.mka")
}

func optimizeAudio(m *Media) bool {
    fmt.Println("Optimize Audio:")
    tmpDir, err := ioutil.TempDir(os.TempDir(), "optimize-")
    defer os.RemoveAll(tmpDir)
    if err != nil {
        fmt.Println(err)
        return false
    }
    vOriginal := filepath.Join(tmpDir, "original.mp4")
    aOriginal := filepath.Join(tmpDir, "original.mka")
    optimized := filepath.Join(tmpDir, "optimized.mp4")
    Copy(m.Video().Path(), vOriginal)
    Copy(m.Path() + "original_audio.mka", aOriginal)
    params := []string{}
    params = append(params, "-i", vOriginal)
    params = append(params, "-i", aOriginal)
    params = append(params, "-map", "0:v")
    params = append(params, "-c:v", "copy")
    params = append(params, "-map", "1:a:0")
    params = append(params, "-c:a", GetParameters().AudioCodec())
    params = append(params, "-filter:a", "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
    params = append(params, "-ab", strconv.Itoa(m.TargetAudioBitrate()))
    params = append(params, "-ac", strconv.Itoa(m.Audio().Channels()))
    params = append(params, "-movflags", "+faststart")
    params = append(params, "-f", "mp4")
    params = append(params, "-y")
    params = append(params, optimized)
    PrintFfmpeg(params)
    fmt.Println("Executing...")
    err = exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
        return false
    }
    err = Move(m.Video().Path(), m.Video().Path() + ".audio.orig") 
    if (err != nil) {
        return false
    }
    err = Move(optimized, m.Path() + m.Name() + ".mp4")
    if (err != nil) {
        Move(m.Video().Path() + ".audio.orig", m.Video().Path())
        return false
    }
    return true
}

func optimizeVideo(m *Media) bool {
    fmt.Println("Optimize Video:")
    tmpDir, err := ioutil.TempDir(os.TempDir(), "optimize-")
    defer os.RemoveAll(tmpDir)
    if err != nil {
        fmt.Println(err)
        return false
    }
    original := filepath.Join(tmpDir, "original.mp4")
    optimized := filepath.Join(tmpDir, "optimized.mp4")
    Copy(m.Video().Path(), original)
    params := []string{}
    if GetParameters().ForceAv1() {
        // This may take some tweaking still.
        // https://www.reddit.com/r/AV1/comments/mxa3vf/first_time_looking_to_encode_in_av1_what_to_use/
        //
        // Accordig to https://goughlui.com/2016/08/27/video-compression-testing-x264-vs-x265-crf-in-handbrake-0-10-5/
        // there’s really no big difference between PSNRs for the average case between x264 and x265 on a CRF value basis.

        // https://engineering.fb.com/2018/04/10/video-engineering/av1-beats-x264-and-libvpx-vp9-in-practical-use-case/
        // x264 CRF = {19, 23, 27, 31, 35, 39}, VP9/AV1 CRF/QP = {27, 33, 39, 45, 51, 57}
        // according to the above mapping, an h264 CRF of 16 == AV1 CRF of 22.5

        // https://brontosaurusrex.github.io/2021/06/05/AV1-encoding-for-dummies/
        // ffmpeg -i "Tears of Steel (2012) copy.webm" -map 0:v:0 -denoise-noise-level 50 -vf format=yuv420p10le,colorspace=bt709:iall=bt2020:fast=1,scale=w=1280:h=720:flags=print_info+spline+full_chroma_inp+full_chroma_int,hqdn3d=1:1:9:9,unsharp=5:5:0.8:3:3:0.4 -vsync 1 -vcodec libaom-av1 -qmin 23 -qmax 63 -b:v 1500000 -maxrate 1848000 -bufsize 3696000 -cpu-used 5 -row-mt true -threads 0 -tile-columns 1 -tile-rows 0 -map 0:a -c:a copy -movflags +faststart -f mp4 -y "Tears of Steel (2012).mp4"
        params = append(params, "-i", original)
        params = append(params, "-map", "0:v:0")
        params = append(params, "-denoise-noise-level", "50")
        params = append(params, "-vf", m.Video().Filter(true))
        params = append(params, "-vsync", "1")
        params = append(params, "-vcodec", "libaom-av1")
        params = append(params, "-qmin", "23")
        params = append(params, "-qmax", "63")
        params = append(params, "-b:v", strconv.Itoa(m.TargetVideoBitrate() - 300000))
        params = append(params, "-maxrate", strconv.Itoa(m.TargetVideoBitrate()))
        params = append(params, "-bufsize", strconv.Itoa(m.TargetVideoBitrate() * 2))
        params = append(params, "-cpu-used", strconv.Itoa(7 - GetParameters().PresetGroup() * 2))
        params = append(params, "-g", "60")
        params = append(params, "-keyint_min", "60")
        params = append(params, "-sc_threshold", "0")
        params = append(params, "-map", "0:a")
        params = append(params, "-c:a", "copy")
        params = append(params, "-movflags", "+faststart")
        params = append(params, "-f", "mp4")
        params = append(params, "-y")
        params = append(params, optimized)
    } else {
        params = append(params, "-i", original)
        params = append(params, "-map", "0:v:0")
        params = append(params, "-vf", m.Video().Filter(true))
        params = append(params, "-vsync", "1")
        params = append(params, "-vcodec", GetParameters().VideoCodec())
        params = append(params, "-r", m.Video().Fps())
        params = append(params, "-crf", "16")
        params = append(params, "-maxrate", strconv.Itoa(m.TargetVideoBitrate()))
        params = append(params, "-bufsize", strconv.Itoa(m.TargetVideoBitrate() * 2))
        params = append(params, "-preset", GetParameters().Preset())
        params = append(params, "-profile:v", GetParameters().VideoProfile())
        if GetParameters().ForceAvc() {
            params = append(params, "-level:v", "4.0")
            params = append(params, "-g", "60")
            params = append(params, "-sc_threshold", "0")
        } else {
            params = append(params, "-x265-params", "level-idc=40:keyint=60:min-keyint=60:scenecut=0")
        }
        params = append(params, "-map", "0:a")
        params = append(params, "-c:a", "copy")
        params = append(params, "-movflags", "+faststart")
        params = append(params, "-f", "mp4")
        params = append(params, "-y")
        params = append(params, optimized)
    }
    PrintFfmpeg(params)
    fmt.Println("Executing...")
    err = exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
        return false
    }
    err = Move(m.Video().Path(), m.Video().Path() + ".orig")
    if (err != nil) {
        return false
    }
    err = Move(optimized, m.Path() + m.Name() + ".mp4")
    if (err != nil) {
        Move(m.Video().Path() + ".orig", m.Video().Path())
        return false
    }
    m.Video().SetPath(m.Path() + m.Name() + ".mp4")
    m.Audio().SetPath(m.Path() + m.Name() + ".mp4")
    return true
}
