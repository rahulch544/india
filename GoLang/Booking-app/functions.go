package main

import (
	"fmt"
)

func main() {

	greetUsers()
	paramFunc("Hi Ram")
	multiParamFunc("rahul", 16)
	temparray := []string{}
	arrayFunc(temparray)

	returnval := returnFuncs("Rahul")

	firstreturn, secondreturn := multiReturnFunc("rahul", "tinku")

}

func greetUsers() {
	fmt.Println("welcome to GOLANG")

}

func paramFunc(param string) {
	fmt.Println("Param", param)
}

func multiParamFunc(param string, intParam int) {
	fmt.Println("String Param", param, "int Param", intParam)
}

func arrayFunc(array []string) {
	fmt.Println("Array", array)
}

// func funcName (params) return type
func returnFuncs(param string) string {
	fmt.Println("Return Function", param)

	return param
}

//  func Multireturns (inputparams) (output return types)

func multiReturnFunc(param1 string, param2 string) (string, int) {

	return param1, 9
}
