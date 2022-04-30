// You can edit this code!
// Click here and start typing.
package main

import "fmt"

func main() {
	obstacles := [][]int32{{5, 5}, {4, 2}, {2, 3}}
	fmt.Println(queensAttack(5, 3, 4, 3, obstacles))

	// fmt.Println(queensAttack(n, k, r_q, c_q, obstacles))
}

func queensAttack(n int32, k int32, rq int32, cq int32, o [][]int32) int32 {

	// Y X
	Y := cq
	X := rq

	// RD = Y - X => cq-rq
	RD := Y - X

	// LD = Y + X => cq+rq
	LD := Y + X

	c := [16]int32{}

	for i := range c {
		c[i] = -1
	}

	for i := int32(0); i < k; i++ {

		x := o[i][0]
		y := o[i][1]

		rd := y - x
		ld := y + x

		if rd == RD {

			if x > X && (c[0] == -1 || c[0] > x) {
				c[0] = x
				c[1] = y
			} else if x < X && (c[2] == -1 || c[2] < x) {
				c[2] = x
				c[3] = y
			}

		} else if ld == LD {

			if x < X && (c[4] == -1 || c[4] < x) {
				c[4] = x
				c[5] = y
			} else if x > X && (c[6] == -1 || c[6] > x) {
				c[6] = x
				c[7] = y
			}
		} else if x == X {

			if y > Y && (c[9] == -1 || c[9] > y) {
				c[8] = x
				c[9] = y
			} else if y < Y && (c[11] == -1 || c[11] < y) {
				c[10] = x
				c[11] = y
			}

		} else if y == Y {

			if x > X && (c[12] == -1 || c[12] > x) {
				c[12] = x
				c[13] = y
			} else if x < X && (c[14] == -1 || c[14] < x) {
				c[14] = x
				c[15] = y
			}
		}

	}

	count := int32(0)
	// fmt.Println(c)
	// fmt.Println("LD,RD", LD, RD)
	cp := [16]int32{n, n, 1, 1, 1, n, n, 1, X, n, 1, n, n, Y, 1, Y}

	if n-RD <= n {
		cp[0] = n - RD
		cp[1] = n
	} else {
		cp[0] = n
		cp[1] = n + RD
	}

	if 1+RD >= 1 {
		cp[2] = 1
		cp[3] = 1 + RD
	} else {
		cp[2] = 1 - RD
		cp[3] = 1
	}

	if (n-LD)*(-1) >= 1 {
		cp[4] = LD - n
		cp[5] = n
	} else {
		cp[4] = 1
		cp[5] = LD - 1
	}

	if (1-LD)*(-1) <= n {
		cp[6] = LD - 1
		cp[7] = 1
	} else {
		cp[6] = n
		cp[7] = LD - n
	}
	// fmt.Println("cp", cp)

	for i := 0; i < 16; i += 2 {

		diff := int32(-1)
		if c[i] == -1 {
			c[i] = cp[i]
			c[i+1] = cp[i+1]
			// continue
			diff = 0
		}

		a := c[i] - X

		if a < X-c[i] {
			a = X - c[i]
		}

		b := c[i+1] - Y

		if b < Y-c[i+1] {
			b = Y - c[i+1]
		}

		if a > b {
			count += a
		} else {
			count += b
		}
		count += diff

	}
	fmt.Println(c)

	return count

}
