package main

import (
	"fmt"
)

func main() {
	fmt.Println("Hello World")
	k := int32(4)
	s := []int32{19, 10, 12, 10, 24, 25, 22}
	fmt.Println(nonDivisibleSubset(k, s))
}
func max(a, b int32) int32 {
	if a < b {
		return b
	} else {
		return a
	}
}
func nonDivisibleSubset(k int32, s []int32) int32 {
	// Write your code here
	// d_arr := make([][]int32, len(s)+1)
	// fmt.Println(d_arr)

	// for i := range d_arr {
	// 	d_arr[i] = make([]int32, len(s)+1)
	// }
	mp := make(map[int32]int32)
	// res := make([]int32, len(s))
	for i := range s {
		s[i] %= k
	}

	fmt.Println(s)
	for i := range s {
		for j := range s {
			if i == j {

				continue
			}
			if (s[i]+s[j])%k == 0 {
				// d_arr[i+1][j+1] = 1
				mp[s[i]] = 1

			}
		}
	}
	final := make([]int32, 0)

	for i := range s {
		if _, ok := mp[int32(s[i])]; !ok {
			final = append(final, s[i])
		}
	}
	fmt.Println(mp)
	fmt.Println(final)
	return int32(len(final))
}
