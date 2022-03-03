package map

import ("strconv")


var bookings =[]string{}

//  Create a map for User
//  map[keyDataType]valueDataType

var userData = make(map[string]string)
// var mymap map[string]string

userData["fName"] = "Rahul"
userData["lName"] = "Chamanthula"
userData["email"] = "rahulch544@gmail.com"
//  convert number(24) into string, with base 10
userData["age"] = strconv.FormatUint(uint64(24),10)

// Map slice  syntax make([]map[string]string,intia size)
var userSlice = make([]map[string]string,0)

