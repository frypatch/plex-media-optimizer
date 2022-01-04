package main

import (
    "strings"
    "strconv"
)

type Crop struct {
	filter string
}

func (c *Crop) Filter() string {
	return c.filter
}

func (c *Crop) Width() int {
	width, _ := strconv.Atoi(strings.Split(strings.Split(c.filter, "crop=")[1], ":")[0])
	return width
}

func (c *Crop) Height() int {
	height, _ := strconv.Atoi(strings.Split(strings.Split(c.filter, ":")[1], ":")[0])
	return height
}
