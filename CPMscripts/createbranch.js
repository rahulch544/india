
let bugNumber = "34030536";
let sprintName = "sprint\\searu2205";
sprintName = "_"+sprintName.replace(/\\/g,"-") + "_";

//console.log(sprintName)
let bugType2 = "hotfix/rchamant_bug-";
let bugType1 = "feature/rchamant_bug-";
let comment = "CLEAR USED PATCH SPACE ON ARU MACHINE ONCE SPB IS BUILT";
comment = "_" + comment.split(" ").join("_");
//comment = "_" + comment.replace(/\s/g,"_");

//hotfix/rchamant_bug_32573342-Insert_LAMP_New_Responsibilities_For_Responsibility_Menu_Feature
//Feature
let featureBranchName = "\n" + bugType1 + bugNumber + sprintName + comment + "\n" ;

console.log(featureBranchName);
//Hotfix branchName 

let hotfixBranchName =  "\n" + bugType2 + bugNumber + comment + "\n";

console.log(hotfixBranchName);
