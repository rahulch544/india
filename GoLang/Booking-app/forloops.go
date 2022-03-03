package forloops

import (
	"fmt"
	"strings"
)

func main() {
	fmt.Printf("Hellow loops")
	// infinte loop

	for {

	}
	// or
	for true {

	}

	// for conditions  {

	// }

	{

		var fName string
		var lName string
		var email string
		var city string

		fmt.Print("Enter First Name, Last Name, email address & City \n")

		fmt.Println("fName")
		fmt.Scan(&fName)
		fmt.Println("lname")
		fmt.Scan(&lName)
		fmt.Println("email")
		fmt.Scan(&email)
		fmt.Println("city")
		fmt.Scan(&city)

		fmt.Println(fName)
		fmt.Println(lName)
		fmt.Println(email)
		fmt.Println(city)

		isValidname := len(fName) >= 2 && len(lName) >= 2

		if !isValidname {
			fmt.Printf("Invalid Name")
		}

		isValidEmail := strings.Contains(email, "@")

		if !isValidEmail {
			fmt.Printf("Invalid Email")
		}

		isInvalidCity := city == "Singapore" || city == "London"

		if !isInvalidCity {
			fmt.Printf("Invalid City")
		}

	}
}
