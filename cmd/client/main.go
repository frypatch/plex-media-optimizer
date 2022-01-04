package main

import (
    "io/ioutil"
    "log"
    "strings"
)

func main() {
    params := ParseFlags()
    params.Println()
    if (!params.Valid()) {
        return
    }
    for _, title := range multipart(params.InputDir()) {
        Concat(params.InputDir(), title)
    }
    for _, movie := range movies(params.InputDir()) {
        Optimize(movie)
    }
}

func multipart(path string) []string {
    movies := make([]string, 0)
    files, err := ioutil.ReadDir(path)
    if err != nil {
        log.Fatal(err)
        return movies
    }
    for _, file := range files {
        if !file.IsDir() {
            continue;
        }
        if GetMedia(path, file.Name()) != nil {
            continue
        }
        files0, err := ioutil.ReadDir(path + file.Name())
        if err != nil {
            log.Fatal(err)
            continue
        }
        out:
        for _, file0 := range files0 {
            for _, extension := range VideoExtensions {
                if strings.HasSuffix(file0.Name(), "." + extension) && strings.Contains(file0.Name(), " - pt") {
                    movies = append(movies, file.Name())
                    break out
                }
            }
        }
    }
    return movies
}

func movies(path string) []*Media {
	movies := make([]*Media, 0)
    files, err := ioutil.ReadDir(path)
    if err != nil {
        log.Fatal(err)
    }
    for _, file := range files {
    	if !file.IsDir() {
	    	continue;
	    }
	    movie := GetMedia(path, file.Name())
	    if movie != nil {
    		movies = append(movies, movie)
	    }
    }
    return movies
}
