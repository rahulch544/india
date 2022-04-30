package main

import (
	"fmt"
	"math"
	"strings"
	"unicode"
)

func main() {

	s := "chillout"
	fmt.Println(encryption(s))
}

func printS(s [][]rune) {

	for _, i := range s {
		for _, j := range i {

			fmt.Printf(string(j))
		}
		fmt.Println("")
	}

}
func encryption(s string) string {
	// Write your code here
	s = strings.ReplaceAll(s, " ", "")

	str_len := float64(len(s))
	sqrt_len := math.Sqrt(str_len)
	row := int32(math.Floor(sqrt_len))
	col := int32(math.Ceil(sqrt_len))

	// p_row := row
	// p_col := col

	for row*col < int32(str_len) {

		// p_row = row
		// p_col = col
		if row < col {
			row++
		} else if col > row {
			col--
		}

	}
	// row = p_row
	// col = p_col

	str := make([][]rune, row)
	for i := range str {
		str[i] = make([]rune, col)
	}

	fmt.Println("sqrt_len,row,col", sqrt_len, row, col)

	c := float64(0)

	for x, i := range str {
		for y, _ := range i {

			if c < str_len {
				str[x][y] = rune(s[int(c)])
			}
			c++
		}
	}

	printS(str)

	r_w := ""

	fmt.Println("col,row", col, row)
	for i := 0; i < int(col); i++ {
		for j := 0; j < int(row); j++ {

			// fmt.Println("J,I", j, i)
			if unicode.IsSpace(str[j][i]) == true {
				break
			}
			r_w += string(str[j][i])
		}
		r_w += " "
	}

	return r_w

}
