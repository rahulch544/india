package struct


// structName  struct{ properties datatypes }
type UserData struct{
	// keys
	fName string
	lName string
	email string
	age uint
	isMale bool

}

var bookings = make([]UserData,0)

var userData = UserData{
	fName: "Rahul",
	lName: "Chamanthula"
	email: "rahulch544@gmail.com",
	age: 0,
	isMale: true

}

var fname = userData.fName

// To stop execution of thread for 10 seconds synchronous thread
time.Sleep(10 * time.Second)

// to support multiple threads