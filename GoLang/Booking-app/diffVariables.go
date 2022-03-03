package main

import (
	"fmt"
)

// Package level variables, Can be accessed in  entire package

var dummy1 string = "dummy"

//  this syntax fails
// dummy2 := "dummy2"

func main() {

	fmt.Println("dummy1", dummy1)
}
