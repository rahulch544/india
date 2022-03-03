  
	var city string

	fmt.Scan(&city)

	switch city {
	case "New York":

	case "London":

	// For two cases one  case block
	case "India", "China":

	case "Pakistan":

	// Default block if all above cases fails
	default:
		fmt.Println("Entered default switch case")
	}