package main

import (
    "os/exec"
    "os"
    "fmt"
    "strings"
)

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
    }
    return target
}
