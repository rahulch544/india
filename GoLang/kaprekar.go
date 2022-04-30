package main

import (
	"fmt"
	"strconv"
	"strings"
)

func main() {
	a := int32(1)
	b := int32(99999)
	kaprekarNumbers(a, b)
}

func kaprekarNumbers(p int32, q int32) {
	// Write your code here

	result := []string{}
	for i := p; i <= q; i++ {
		if i == 1 {
			result = append(result, strconv.Itoa(int(i)))
			continue
		}
		l_b := len(strconv.Itoa(int(i)))
		x := int64(i)
		x *= x

		s := strconv.Itoa(int(x))

		l_a := len(s)
		// fmt.Println("x,s,l_b,l_a", x, s, l_b, l_a)
		if l_b*2 == l_a || l_b*2-1 == l_a {
			// if l_b*2-1 == l_a {
			// 	s += "0"
			// }

			A, _ := strconv.ParseInt(s[:l_a-l_b], 10, 32)
			B, _ := strconv.ParseInt(s[l_a-l_b:], 10, 32)

			// fmt.Println("A,B", A, B, s[:l_a-l_b], s[l_a-l_b:])
			if int32(A+B) == i {
				result = append(result, strconv.Itoa(int(i)))
			}
		} else {
			continue
		}
	}

	if len(result) > 0 {
		fmt.Println(strings.Join(result[:], " "))
	} else {
		fmt.Println("INVALID RANGE")
	}
}
