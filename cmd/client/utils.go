package main

import (
    "io/ioutil"
    "os/exec"
    "os"
    "fmt"
    "strings"
    "bufio"
    "runtime"
    "path/filepath"
)

func GetBrand() string {
    return "Armchair"
}

// DefaultMetadataDir returns the default data directory of armchair. The values for
// supported operating systems are:
//
// Linux:   $HOME/.armchair
// MacOS:   $HOME/Library/Application Support/Armchair
// Windows: %LOCALAPPDATA%\Armchair
//
// Might need to use "github.com/mitchellh/go-homedir" to get the home directory
func DefaultMetadataDir() string {
    path := ""
    switch runtime.GOOS {
        case "windows":
            path = filepath.Join(os.Getenv("LOCALAPPDATA"), GetBrand())
        case "darwin":
            path = filepath.Join(os.Getenv("HOME"), "Library", "Application Support", GetBrand())
        default:
            path = filepath.Join(os.Getenv("HOME"), "." + strings.ToLower(GetBrand()))
    }
    if path != "" && !PathExists(path) {
        path = Mkdir(path)
    }
    return path
}

func PathExists(path string) bool {
    if _, err := os.Stat(path); err == nil {
        return true
    }
    return false
}

func PrintFfprobe(params []string) {
    fmt.Print("ffprobe")
    for i, param := range params {
        if strings.HasPrefix(param, "-") || i + 1 == len(params) {
            fmt.Print("\n  " + param)
        } else {
            fmt.Print(" " + param)
        }
    }
    fmt.Println("")
}

func PrintFfmpeg(params []string) {
    fmt.Print("ffmpeg")
    for i, param := range params {
        if strings.HasPrefix(param, "-") || i + 1 == len(params) {
            fmt.Print("\n  " + param)
        } else {
            fmt.Print(" " + param)
        }
    }
    fmt.Println("")
}

func Copy(from string, to string) bool {
    err := exec.Command("cp", from, to).Run()
    return err == nil
}

func Move(from string, to string) error {
    return exec.Command("mv", from, to).Run()
}

func Remove(target string) bool {
    err := exec.Command("rm", "-rf", target).Run()
    return err == nil
}

func Write(target string, text string) bool {
    err := os.WriteFile(target, []byte(text), 0644)
    if err != nil {
        fmt.Println("Failed to write to temporary file: %v", err)
        return false
    }
    return true
}

func Mkdir(target string) string {
    err := os.MkdirAll(target, os.ModePerm)
    if err != nil {
        fmt.Println("Failed to make directory: %v", err)
        return ""
    }
    return target
}

func MkTmpDir() string {
    tmpDir, err := ioutil.TempDir(os.TempDir(), GetBrand())
    if err != nil {
        fmt.Println("Failed to make temporary directory: %v", err)
        return ""
    }
    return tmpDir
}

func Read(target string) []string {
    file, err := os.Open(target)
    if err != nil {
        fmt.Println("Failed to open file: %s", target)
    }
    scanner := bufio.NewScanner(file)
    scanner.Split(bufio.ScanLines)
    var lines []string
    for scanner.Scan() {
        lines = append(lines, scanner.Text())
    }
    file.Close()
    return lines
}
