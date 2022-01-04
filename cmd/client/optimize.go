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
