package main

import (
    "fmt"
    "os"
    "os/exec"
    "strings"
    "io/ioutil"
    "path/filepath"
    "flag"
    "strconv"
    "runtime"
)

var VideoExtensions []string = []string{"mp4", "mkv", "webm"}
var PresetValues string = " ultrafast superfast veryfast faster fast medium slow slower veryslow placebo "
var params *Parameters

type Parameters struct {
    path        string
    filter      string
    bitrate     int
    cores       int
    gop         int
    force8Bit   bool
    forceAvc    bool
    forceAv1    bool
    dryRun      bool
    skipCleanup bool
    skipCrop    bool
    skipDecomb  bool
    skipDenoise bool
    skipNnedi   bool
    help        bool
    preset      string
    acodec      string
}

func ParseFlags() *Parameters {
    pathPtr := flag.String("path", "unknown", "The path to the directory to scan.")
    filterPtr := flag.String("filter", ".*", "A regex value. Only scan movies whose title matches this value.")
    bitrarePtr := flag.Int("bitrate", 2000000, "Maximum bitrate of the resulting video.")
    coresPtr := flag.Int("cores", 0, "Number of CPU cores to use to encode the video. Defaults to one less than the total number of CPU cores.")
    gopPtr := flag.Int("gop", 250, "Maximum number of frames before forcing a keyframe. Larger values increase visual quality.")
    force8BitPtr := flag.Bool("force8Bit", false, "Supply this flag when the resulting video's color depth should be 8-bit instead of 10-bit.")
    forceAvcPtr := flag.Bool("forceAvc", false, "Supply this flag when the resulting video's codec should be AVC instead of HEVC.")
    forceAv1Ptr := flag.Bool("forceAv1", false, "Supply this flag when the resulting video's codec should be AV1 instead of HEVC.")
    dryRunPtr := flag.Bool("dryRun", false, "Supply this flag when the video encoding step should be skipped.")
    skipCleanupPtr := flag.Bool("skipCleanup", false, "Supply this flag when the original videos should not be discarded.")
    skipCropPtr := flag.Bool("skipCrop", false, "Supply this flag when letter-box bars in the source video should not be removed.")
    skipDecombPtr := flag.Bool("skipDecomb", false, "Supply this flag when interlaced video should not be converted to progressive video.")
    skipDenoisePtr := flag.Bool("skipDenoise", false, "Supply this flag when the denoiser should not be used before scaling the video.")
    skipNnediPtr := flag.Bool("skipNnedi", false, "Supply this flag when the nnedi upscaler not be used to scale the video.")
    presetPtr := flag.String("preset", "slow", "The preset to use. Slower preset values will produce better video quality. Valid preset values are:" + PresetValues)
    flag.Parse()
    params = &Parameters{}
    params.path = *pathPtr
    params.filter = *filterPtr
    params.bitrate = *bitrarePtr
    params.gop = *gopPtr
    params.cores = *coresPtr
    params.force8Bit = *force8BitPtr
    params.forceAvc = *forceAvcPtr
    params.forceAv1 = *forceAv1Ptr
    params.dryRun = *dryRunPtr
    params.skipCleanup = *skipCleanupPtr
    params.skipCrop = *skipCropPtr
    params.skipDecomb = *skipDecombPtr
    params.skipDenoise = *skipDenoisePtr
    params.skipNnedi = *skipNnediPtr
    params.preset = *presetPtr
    return params
}

func GetParameters() *Parameters {
    return params
}

func (p *Parameters) Println() {
    fmt.Println("path:", p.path)
    fmt.Println("filter:", p.filter)
    fmt.Println("bitrate:", p.bitrate)
    fmt.Println("cores:", p.Cores())
    fmt.Println("gop:", p.gop)
    fmt.Println("force8Bit:", p.force8Bit)
    fmt.Println("forceAvc:", p.forceAvc)
    fmt.Println("forceAv1:", p.forceAv1)
    fmt.Println("dryRun:", p.dryRun)
    fmt.Println("skipCleanup:", p.skipCleanup)
    fmt.Println("skipDenoise:", p.skipDenoise)
    fmt.Println("skipDecomb:", p.skipDecomb)
    fmt.Println("skipCrop:", p.skipCrop)
    fmt.Println("preset:", p.preset)
}

func (p *Parameters) InputDir() string {
    return p.path
}

func (p *Parameters) Filter() string {
    return p.filter
}

func (p *Parameters) Bitrate() int {
    return p.bitrate
}

func (p *Parameters) Cores() int {
    if p.cores < 1 {
        p.cores = runtime.NumCPU() - 1
    }
    if p.cores < 1 {
        p.cores = 1
    }
    runtime.GOMAXPROCS(p.cores)
    return p.cores
}

func (p *Parameters) GOP() string {
    return strconv.Itoa(p.gop)
}

func (p *Parameters) Force8Bit() bool {
    return p.force8Bit
}

func (p *Parameters) ForceAvc() bool {
    return p.forceAvc
}

func (p *Parameters) ForceHevc() bool {
    return !p.forceAvc && !p.forceAv1
}

func (p *Parameters) ForceAv1() bool {
    return p.forceAv1
}

func (p *Parameters) DryRun() bool {
    return p.dryRun
}

func (p *Parameters) Denoise() bool {
    return !p.skipDenoise
}

func (p *Parameters) Decomb() bool {
    return !p.skipDecomb
}

func (p *Parameters) Crop() bool {
    return !p.skipCrop
}

func (p *Parameters) Nnedi() bool {
    return !p.skipNnedi
}

func (p *Parameters) Help() bool {
    return p.help
}

func (p *Parameters) Ultrafast() bool {
    return p.preset == "ultrafast"
}

func (p *Parameters) Preset() string {
    // TODO: add sanity check
    return p.preset
}

func (p *Parameters) Valid() bool {
    if !strings.Contains(PresetValues, " " + p.preset + " ") {
        fmt.Println("ILLEGAL PRESET:", p.preset)
        return false
    }
    return true
}

func (p *Parameters) PresetGroup() int {
    if strings.Contains(" ultrafast superfast veryfast faster ", " " + p.preset + " ") {
        return 0
    }
    if strings.Contains(" fast medium slow ", " " + p.preset + " ") {
        return 1
    }
    if strings.Contains(" slower veryslow placebo ", " " + p.preset + " ") {
        return 2
    }
    return -1
}

func (p *Parameters) ScalingAlgo() string {
    if p.PresetGroup() == 0 {
        return "bicubic"
    }
    return "spline"
}

func (p *Parameters) VideoProfile() string {
    if p.force8Bit {
        return "main"
    } else if p.forceAvc {
        return "high10"
    } else {
        return "main10"
    }
}

func (p *Parameters) VideoCodec() string {
    if p.forceAvc == true {
        return "libx264"
    } else if p.forceAv1 == true {
        return "libaom-av1"
    } else {
        return "libx265"
    }
}

func (p *Parameters) AudioCodec() string {
    if p.acodec != "" {
        return p.acodec
    }
    cmd := exec.Command("ffmpeg", "-version")
    stdout, _ := cmd.Output()
    if strings.Contains(string(stdout), "--enable-libopus") {
        p.acodec = "libopus"
    } else {
        p.acodec = "aac"
    }
    return p.acodec
}

func (p *Parameters) Cleanup(path string) {
    if p.skipCleanup {
        return
    }
    files, err := ioutil.ReadDir(path)
    if err != nil {
        fmt.Println(err)
        return
    }
    for _, file := range files {
        if file.Name() == "orig" {
            fmt.Println("Discarding original files stored in:", filepath.Join(path, file.Name()))
            os.RemoveAll(filepath.Join(path, file.Name()))
        } else if strings.HasSuffix(file.Name(), ".orig") {
            fmt.Println("Discarding original file:", filepath.Join(path, file.Name()))
            os.Remove(filepath.Join(path, file.Name()))
        }
    }
}
