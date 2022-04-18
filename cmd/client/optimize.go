package main

import (
    "io/ioutil"
    "path/filepath"
    "fmt"
    "os/exec"
    "os"
    "strconv"
    "strings"
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
    params = append(params, "-ab", strconv.Itoa(m.MaxAudioBitrate()))
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
    fmt.Println("Optimizing", m.Name())
    path := filepath.Join(DefaultMetadataDir(), m.Name())
    if (!PathExists(path)) {
        Mkdir(path)
    }
    defer os.RemoveAll(path)
    original := &Video{}
    original.SetPath(filepath.Join(path, "original.mp4"))
    if !PathExists(original.Path()) {
        Copy(m.Video().Path(), original.Path())
    }
    optimized := filepath.Join(path, "optimized.mp4")
    original.DetectCrop()
    scenes := ""
    for _, scene := range optimizeScenes(path, original, m.MaxVideoBitrate()) {
        scenes = scenes + fmt.Sprintf("file '%v'\n", scene.Path())
    }
    tmpFiles, _ := ioutil.TempDir(os.TempDir(), GetBrand())
    defer os.RemoveAll(tmpFiles)
    Write(filepath.Join(tmpFiles, "scenes.txt"), scenes)
    params := []string{}
    params = append(params, "-f", "concat")
    params = append(params, "-safe", "0")
    params = append(params, "-i", filepath.Join(tmpFiles, "scenes.txt"))
    params = append(params, "-c", "copy")
    params = append(params, optimized)
    // PrintFfmpeg(params)
    // fmt.Println("Executing...")
    err := exec.Command("ffmpeg", params...).Run()
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

func detectScenes(target string, v *Video) {
    fmt.Println("Detecting Scenes...")
    detectScenes := []string{}
    detectScenes = append(detectScenes, "ffprobe")
    detectScenes = append(detectScenes, "-show_frames")
    detectScenes = append(detectScenes, "-show_entries", "frame=best_effort_timestamp_time")
    detectScenes = append(detectScenes, "-of", "compact=p=0")
    detectScenes = append(detectScenes, "-f", "lavfi", fmt.Sprintf(`"movie=%s,select=gt(scene\,0.5)"`, v.Path()))
    detectScenes = append(detectScenes, ">", fmt.Sprintf(`"%s"`, target))
    // fmt.Println(strings.Join(detectScenes, " "))
    err := exec.Command("bash","-c",strings.Join(detectScenes, " ")).Run()
    if err != nil {
        fmt.Println(err)
    }
}

func optimizeScenes(path string, v *Video, maxBitrate int) []*Video {
    detectedScenes := filepath.Join(path, "scenes.txt")
    if !PathExists(detectedScenes) {
        detectScenes(detectedScenes, v)
    }
    cores := GetParameters().Cores()
    minDuration := float64(300)
    if thisDuration, _ := strconv.ParseFloat(v.Duration(), 64); thisDuration / float64(cores) < minDuration {
        minDuration = thisDuration / float64(cores)
    }
    prevTime := float64(0)
    detectedTimes := make([]string, 0)
    for _, detectedScene := range Read(detectedScenes) {
        meta := strings.Split(detectedScene, "|")
        time := strings.TrimPrefix(meta[0], "best_effort_timestamp_time=")
        score := strings.TrimPrefix(meta[1], "tag:lavfi.scene_score=")
        if thisTime, _ := strconv.ParseFloat(time, 64); thisTime - prevTime > minDuration {
            detectedTimes = append(detectedTimes, time)
            fmt.Println("scene", len(detectedTimes), time, score)
            prevTime = thisTime
        }
    }
    detectedTimes = append(detectedTimes, v.Duration())
    fmt.Println("scene", len(detectedTimes), v.Duration(), "1.000000")
    // Create a bounded channel, limit that channel to 5 cores.
    // source: https://medium.com/@deckarep/gos-extended-concurrency-semaphores-part-1-5eeabfa351ce
    var sem = make(chan int, cores)
    start := "0"
    scenes := make([]*Video, 0)
    for i, end := range detectedTimes {
        scene := Video{}
        scene.SetPath(v.Path() + ".pt" + strconv.Itoa(i))
        scenes = append(scenes, &scene)
        sem <- 1
        go func(v *Video, start string, end string, i int) {
            optimizeScene(v, maxBitrate, start, end, i)
            <-sem
        }(v, start, end, i)
        start = end
    }
    // Fill the bounded channel up which forces us to block until all threads have finished.
    for i := 0; i < cores; i++ {
        sem <- 1
    }
    // Clear the bounded channel. Probably not needed.
    for i := 0; i < cores; i++ {
        <-sem
    }
    return scenes
}

func optimizeScene(v *Video, maxBitrate int, start string, end string, count int) {
    if PathExists(v.Path() + ".pt" + strconv.Itoa(count)) {
        return
    }
    fmt.Println("Optimizing scene: ", start, end, count)
    startEstimate, _ := strconv.ParseFloat(start, 64)
    startEstimate = startEstimate - float64(3)
    params := []string{}
    // https://stackoverflow.com/questions/21420296/how-to-extract-time-accurate-video-segments-with-ffmpeg
    // Just supplying the -ss and -to parameters before the input value to enable keyframe seeking 
    // should be fince since we are obtaining the times to split on by finding keyframes with large
    // amounts change from the previous frame.
    params = append(params, "-ss", start)
    params = append(params, "-to", end)
    params = append(params, "-i", v.Path())
    params = append(params, "-map", "0:v:0")
    if GetParameters().ForceAv1() {
        // https://brontosaurusrex.github.io/2021/06/05/AV1-encoding-for-dummies/
        // Setting the denoise-noise-level parameter enables grain synthesis.
        // This needs to be set before the video filter because the video filter does scaling 
        // and we want to denoise the video before scaling the video.
        params = append(params, "-denoise-noise-level", "50")
    }
    // Add video filters such as scaling, denoising, and deinterlacing.
    params = append(params, "-vf", v.Filter(true))
    // Setting vsync to 1 forces a constant frame rate.
    params = append(params, "-vsync", "1")
    // Limit threads here; we are using parallel processing of multiple scenes instead of 
    // ffmpeg's native multithreading. This is needed because a lot of the video filters 
    // are slow because they are not multi-threaded.
    params = append(params, "-threads", "1")
    params = append(params, "-vcodec", GetParameters().VideoCodec())
    params = append(params, "-r", v.Fps())
    if GetParameters().ForceAv1() {
        // Setting the lag-in-frames to 25 lets the AV1 codec look ahead 25 frames into the future.
        // Higher values improve visual quality.
        params = append(params, "-lag-in-frames", "25")
        // Enable use of alternate reference frames.
        params = append(params, "-auto-alt-ref", "1")
        // https://engineering.fb.com/2018/04/10/video-engineering/av1-beats-x264-and-libvpx-vp9-in-practical-use-case/
        // x264 CRF = {19, 23, 27, 31, 35, 39}, VP9/AV1 CRF/QP = {27, 33, 39, 45, 51, 57}
        // according to the above mapping, an h264 CRF of 16 == AV1 CRF of 22.5
        // Do not try for a better quality than 23; doing throw is wasting bits on diminishing 
        // returns as a qmin of 23 for the AV1 codec is already considered visually lossless.
        params = append(params, "-qmin", "23")
        // Do not limit the worst case visual quality scenario as this will be capped by the max 
        // bitrate.
        params = append(params, "-qmax", "63")
        // Set the quality/encoding speed tradeoff. Valid range is from 0 to 8, higher numbers 
        // indicating greater speed and lower quality.
        // * Presets of ultrafast to faster use a value of 7.
        // * Presets of fast to slow use a value of 4.
        // * presets of slower to placebo use a value of 1.
        params = append(params, "-cpu-used", strconv.Itoa(7 - GetParameters().PresetGroup() * 3))
        // Set the max frames between keyframes
        params = append(params, "-g", GetParameters().GOP())
        // Set average bitrate to be 250kbps less than the max bitrate.
        params = append(params, "-b:v", strconv.Itoa(maxBitrate - 250000))
    } else {
        // Accordig to https://goughlui.com/2016/08/27/video-compression-testing-x264-vs-x265-crf-in-handbrake-0-10-5/
        // there’s really no big difference between PSNRs for the average case between x264 and x265 on a CRF value basis.
        params = append(params, "-crf", "16")
        params = append(params, "-preset", GetParameters().Preset())
        params = append(params, "-profile:v", GetParameters().VideoProfile())
        if GetParameters().ForceAvc() {
            // Set the video level to 4.0 as its a good balance between compatability and quality.
            params = append(params, "-level:v", "4.0")
            // Set the max frames between keyframes.
            params = append(params, "-g", GetParameters().GOP())
        } else if GetParameters().ForceHevc() {
            h265Params := []string{}
            // Set the video level to 4.0 as its a good balance between compatability and quality.
            h265Params = append(h265Params, "level-idc=40")
            // Set the max frames between keyframes.
            h265Params = append(h265Params, "keyint=" + GetParameters().GOP())
            // These values need to be supplied to the x265 codec directly.
            params = append(params, "-x265-params", strings.Join(h265Params, ":"))
        }
    }
    // Setting the maxrate parameter caps to 50kbps less than the maximum bitrate.
    // This gives us a little bit of wiggle room to stay under the cap without needing to do two passes.
    params = append(params, "-maxrate", strconv.Itoa(maxBitrate - 50000))
    // Cap max buffer size to twice the max bitrate.
    // Having a buffer allows us to increase our quality as we are able to pre-load the buffer
    // with additional quality whenever the bitrate is not maxed.
    params = append(params, "-bufsize", strconv.Itoa(maxBitrate * 2))
    params = append(params, "-map", "0:a")
    params = append(params, "-c:a", "copy")
    params = append(params, "-movflags", "+faststart")
    params = append(params, "-f", "mp4")
    params = append(params, "-y")
    params = append(params, v.Path() + ".tmp.pt" + strconv.Itoa(count))
    //PrintFfmpeg(params)
    //fmt.Println("Executing...")
    err := exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
    }
    err = Move(v.Path() + ".tmp.pt" + strconv.Itoa(count), v.Path() + ".pt" + strconv.Itoa(count))
    if err != nil {
        fmt.Println(err)
    }
}
