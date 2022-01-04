package main

import (
    "io/ioutil"
    "log"
    "path/filepath"
    "fmt"
    "os/exec"
    "os"
    "strconv"
    "strings"
)

func Concat(path string, title string) {
    fmt.Printf("### Concatenating %s.\n", title)
    if GetParameters().DryRun() {
        return
    }
    tmpDir, _ := ioutil.TempDir(os.TempDir(), "optimize")
    defer os.RemoveAll(tmpDir)
    videos := findAll(path, title)
    if !scaleAll(videos) {
        fmt.Println("Could not scale all videos.")
        return
    }
    if !copyAll(videos, tmpDir) {
        fmt.Println("Could not copy all videos.")
        return
    }
    if !sanitizeAll(videos) {
        fmt.Println("Could not sanitize all videos.")
        return
    }
    if !joinAll(videos, title, filepath.Join(tmpDir, "concat.mp4")) {
        fmt.Println("Could not join all videos.")
        return
    }
    moveAll(
        findAll(path, title),
        Mkdir(filepath.Join(filepath.Join(path, title), "orig")))
    Move(
        filepath.Join(tmpDir, "concat.mp4"),
        filepath.Join(filepath.Join(path, title), title) + ".mp4")
    GetParameters().Cleanup(filepath.Join(path, title))
}

func findAll(path string, title string) []*Video {
    videos := make([]*Video, 0)
    for i := 0; i < 9000; i++ {
        files, err := ioutil.ReadDir(path + title)
        if err != nil {
            log.Fatal(err)
            continue
        }
        for _, file := range files {
            for _, extension := range VideoExtensions {
                suffix := fmt.Sprintf(" - pt%v.%s", i, extension)
                if strings.HasSuffix(file.Name(), suffix) {
                    v := Video{}
                    v.name = strings.TrimSuffix(file.Name(), suffix)
                    v.path = path + title + "/" + file.Name()
                    videos = append(videos, &v)
                }
            }
        }
    }
    return videos
}

func scaleAll(videos []*Video) bool {
    for _, v := range videos {
        if !scale(v) {
            return false
        }
    }
    return true
}

func copyAll(videos []*Video, toDir string) bool {
    for i, v := range videos {
        toFilePath := filepath.Join(toDir, strconv.Itoa(i + 1000) + ".mp4")
        if (!Copy(v.Path(), filepath.Join(toDir, strconv.Itoa(i + 1000) + ".mp4"))) {
            return false
        }
        v.SetPath(toFilePath)
    }
    return true
}

func sanitizeAll(videos []*Video) bool {
    fps := videos[0].Fps()
    w, h, c, dar := max(videos)
    for _, v := range videos {
        if !sanitize(v, fps, w, h, c, dar) {
            return false
        }        
    }
    return true
}

func joinAll(videos []*Video, title string, to string) bool {
    tmpFiles, _ := ioutil.TempDir(os.TempDir(), "join")
    defer os.RemoveAll(tmpFiles)
    Write(filepath.Join(tmpFiles, "files.txt"), files(videos))
    Write(filepath.Join(tmpFiles, "metadata.txt"), metadata(title, videos))
    fmt.Println("tmpFiles", tmpFiles)
    params := []string{}
    params = append(params, "-f", "concat")
    params = append(params, "-safe", "0")
    params = append(params, "-i", filepath.Join(tmpFiles, "files.txt"))
    params = append(params, "-i", filepath.Join(tmpFiles, "metadata.txt"))
    params = append(params, "-map_metadata", "1")
    params = append(params, "-c", "copy")
    params = append(params, to)
    PrintFfmpeg(params)
    err := exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
        return false
    }
    return true
}

func moveAll(videos []*Video, toDir string) bool {
    for _, v := range videos {
        err := Move(v.Path(), toDir)
        if err != nil {
            fmt.Println("Failed to move %v to %v: %v", v.Path(), toDir, err)
        }
    }
    return true
}

func scale(v *Video) bool {
    if v.Width() > 959 && v.Height() > 547 {
        return true
    }
    fmt.Printf("Scale Video %s.\n", v.Name())
    tmpDir, _ := ioutil.TempDir(os.TempDir(), "optimize-")
    defer os.RemoveAll(tmpDir)
    original := filepath.Join(tmpDir, "original.mp4")
    optimized := filepath.Join(tmpDir, "optimized.mp4")
    Copy(v.Path(), original)
    params := []string{}
    params = append(params, "-i", original)
    params = append(params, "-map", "0:v:0")
    params = append(params, "-vf", v.Filter(true))
    params = append(params, "-vsync", "1")
    params = append(params, "-vcodec", "libx264")
    params = append(params, "-r", v.Fps())
    // preset group 0 has -crf 16; preset group 1 has -crf 10; preset group 2 has -crf 4.
    params = append(params, "-crf", strconv.Itoa(16 - GetParameters().PresetGroup() * 6))
    params = append(params, "-preset", GetParameters().Preset())
    params = append(params, "-profile:v", "high10")
    params = append(params, "-level:v", "6.1")
    params = append(params, "-map", "0:a")
    params = append(params, "-c:a", "copy")
    params = append(params, "-f", "mp4")
    params = append(params, "-y")
    params = append(params, optimized)
    PrintFfmpeg(params)
    fmt.Println("Executing...")
    err := exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
        return false
    }
    err = Move(v.Path(), v.Path() + ".orig")
    if (err != nil) {
        return false
    }
    err = Move(optimized, v.Path())
    if (err != nil) {
        Move(v.Path() + ".orig", v.Path())
        return false
    }
    return true
}

func sanitize(v *Video, fps string, w int, h int, c int, dar float64) bool {
    a := Audio{}
    a.path = v.path
    vf := ""
    vf = vf + fmt.Sprintf("scale=(iw*sar)*min(%v/(iw*sar)\\,%v/ih):ih*min(%v/(iw*sar)\\,%v/ih):flags=print_info+spline+full_chroma_inp+full_chroma_int,",w, h, w, h)
    vf = vf + fmt.Sprintf("pad=%v:%v:(%v-iw*min(%v/iw\\,%v/ih))/2:(%v-ih*min(%v/iw\\,%v/ih))/2", w, h, w, w, h, w, w, h)
    Move(v.path, v.path + ".orig")
    params := []string{}
    params = append(params, "-i", v.path + ".orig")
    params = append(params, "-map", "0:v:0")
    params = append(params, "-map", "-0:t") // remove attachments
    params = append(params, "-vf", vf)
    params = append(params, "-vsync", "1")
    params = append(params, "-vcodec", "libx264")
    params = append(params, "-r", fps)
    // preset group 0 has -crf 16; preset group 1 has -crf 10; preset group 2 has -crf 4.
    params = append(params, "-crf", strconv.Itoa(16 - GetParameters().PresetGroup() * 6))
    params = append(params, "-preset", GetParameters().Preset())
    params = append(params, "-profile:v", "high10")
    params = append(params, "-level:v", "6.1")
    params = append(params, "-g", "60")
    params = append(params, "-sc_threshold", "0")
    params = append(params, "-map", "0:a:0")
    params = append(params, "-c:a", GetParameters().AudioCodec())
    params = append(params, "-filter:a", "aresample=async=1:min_hard_comp=0.100000:first_pts=0")
    params = append(params, "-ab", "600k")
    params = append(params, "-ac", strconv.Itoa(c))
    params = append(params, "-ar", "48000")
    params = append(params, "-f", "mp4")
    params = append(params, "-y")
    params = append(params, v.path)
    PrintFfmpeg(params)
    err := exec.Command("ffmpeg", params...).Run()
    if err != nil {
        fmt.Println(err)
        return false
    }
    return true
}

func max(videos []*Video) (int, int, int, float64) {
    w := 0
    h := 0
    c := 0
    d := float64(0)
    for _, v := range videos {
        a := Audio{}
        a.path = v.path
        if (a.Channels() > c) {
            c = a.Channels()
        }
        if (v.Width() > w) {
            w = v.Width()
        }
        if (v.Height() > h) {
            h = v.Height()
        }
        if (v.Dar() > d) {
            d = v.Dar()
        }
    }
    // When the DAR is larger than 16:9 then the width fills the frame and the height should be proportional.
    // Otherwise the height fills the frame and the width should be proportional.
    if d > 1.777 {
        h = int(float64(w) / d)
    } else {
        w = int(float64(h) * d)
    }
    return w, h, c, d
}

func metadata(title string, videos []*Video) string {
    chapterData := ";FFMETADATA1\n"
    chapterData = chapterData + fmt.Sprintf("title=%s\n\n", title)
    start := 0
    end := 0
    for i, v := range videos {
        end = end + v.Duration()
        chapterData = chapterData + "[CHAPTER]\n"
        chapterData = chapterData + "TIMEBASE=1/1000\n"
        chapterData = chapterData + fmt.Sprintf("START=%v\n", start)
        chapterData = chapterData + fmt.Sprintf("END=%v\n", end)
        chapterData = chapterData + fmt.Sprintf("title=CHAPTER %v: %s\n\n", i + 1, v.Name())
        start = end
    }
    // TrimSuffix will only trim the last match.
    // TrimRight will trim multiple all matches
    // return strings.TrimSuffix(chapterData, "\n")
    return strings.TrimRight(chapterData, "\n")
}

func files(videos []*Video) string {
    files := ""
    for _, v := range videos {
        files = files + fmt.Sprintf("file '%v'\n", v.Path())
    }
    return files
}
