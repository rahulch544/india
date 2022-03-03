package main

// to use print/input function we have to import libaries, on click we can go to link
// For unused imports we see error
import (
	"booking-app/helper"
	"fmt"
	"strings"
)

// Entry point of go lang will have function named go,
// these we are execution starts from multiple files
func main() {

	helper.Helperfunc()
	fmt.Print("Hellor World ")
	fmt.Print("Same line ")
	fmt.Println("ends with new line character ")
	fmt.Print("Same line ")
	fmt.Println("New line ")

	// declaration of variable, For unused variables we see error, conference variable can be referenced anywhere
	var conferenceName = "Go Conference"
	fmt.Println(conferenceName)
	//  Memory address
	fmt.Println(&conferenceName)
	fmt.Println("Welcome to ", conferenceName, "Booking Application")

	//  Constants same across every where
	const conferenceTickets = 50

	//  Constants same across every where
	const conferenceTicketsDummy int = 50

	// Print type of variables
	fmt.Printf("ConferenceTickets %T conferenceName %T conferenceTicketsDummy %T ", conferenceTickets, conferenceName, conferenceTicketsDummy)

	var remainingTickets = conferenceTickets

	fmt.Println("We have total of ", conferenceTickets)
	fmt.Println("Remaining Available tickets ", remainingTickets)

	fmt.Printf("welcome to  %v booking application \n", conferenceName)
	fmt.Printf("Testing this printf funciton   %v Order is imp %v \n", conferenceName, conferenceTickets)

	// User Input values to golang, When variables are declared without assignment it needs to be declared type
	var userName string
	var userTickets int
	var email string
	var phone string
	// ask user for their named by input method
	fmt.Printf("Please enter user name \n")
	fmt.Scan(&userName)
	fmt.Printf("Please enter no of tickets require \n")
	fmt.Scan(&userTickets)
	remainingTickets = remainingTickets - userTickets
	fmt.Printf("Please enter  email id \n")
	fmt.Scan(&email)
	fmt.Printf("Please enter  phone number \n")
	fmt.Scan(&phone)

	fmt.Printf("Username inputed %v this many tickets %v \n", userName, userTickets)
	fmt.Printf("Remaining tickets avaialble are %v \n", remainingTickets)

	// Basic Data types in golang are String and Integers which are basic
	// int , uint, float

	// variable declaration
	var directDeclaration1 = 50
	var directDeclaration2 int = 100
	// following delcartion will not applicable to  Constants
	directDeclaration3 := 150

	fmt.Printf("directDeclaration1 %v directDeclaration2 %v directDeclaration3 %v\n", directDeclaration1, directDeclaration2, directDeclaration3)

	// Arrays  & slices
	// Arrays are fixed size
	// var arryaName = [len]type{intial values} or
	//  var arryaName [len]type{}
	// Array of size 50 strings with 3 inputs as values
	var bookings = [50]string{"rahul chamanthula", "Nicole efefef ", "Peter fefe"}

	bookings[4] = userName + " Booked ticket"

	fmt.Printf("The whole array : %v\n", bookings)
	fmt.Printf("THe First Booking: %v\n", bookings[0])
	fmt.Printf("Array type: %T \n", bookings)
	fmt.Printf("Length of array: %v\n", len(bookings))

	// Slices with dynamic size, can be defined similar to array
	var bookings_slice []string
	bookings_slice = append(bookings_slice, "Rahul")
	fmt.Printf("Bookings_slice : %v \n", bookings_slice)
	//
	// indefinte can be breaked with break statementand remaining iteration  code to skip add continue
	for {
		var fName string
		var lName string
		var email string
		var pNumber string
		var ntickets int
		fmt.Printf("fname\n")
		fmt.Scan(&fName)
		fmt.Printf("lName\n")
		fmt.Scan(&lName)
		fmt.Printf("email\n")
		fmt.Scan(&email)
		fmt.Printf("pNumber\n")
		fmt.Scan(&pNumber)
		fmt.Printf("ntickets\n")
		fmt.Scan(&ntickets)

		//slice
		firstNames := []string{}
		// _ to ignore index variable
		for _, booking := range bookings_slice {
			//  Strings.Fileds seperates booking element on space and returns slice
			var names = strings.Fields(booking)
			fmt.Println("names", names)
			// firstNames = append(firstNames, names[0])
		}
		fmt.Printf("Bookings firstNames : %v \n", firstNames)
		remainingTickets = remainingTickets - ntickets
		noTickets := remainingTickets == 0
		if noTickets {
			fmt.Printf("ended here")
			break
		}

	}

	// If else statement
	if remainingTickets == 0 {
		fmt.Println("If  statement syntax")
	} else if remainingTickets > 0 {
		fmt.Println("else if statement syntax")
	} else {
		fmt.Println("else statement syntax")
	}

}
