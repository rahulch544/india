
let bugNumber = "33905709";
let sprintName = "sprint\\searu2203";
sprintName = "_"+sprintName.replace(/\\/g,"-") + "_";

//console.log(sprintName)
let bugType2 = "hotfix/rchamant_bug-";
let bugType1 = "feature/rchamant_bug-";
let comment = "Process Delta Content  self Service does not allow to do a branching for 12.2.0.1.0 Releases.";
comment = "_" + comment.split(" ").join("_");
//comment = "_" + comment.replace(/\s/g,"_");

//hotfix/rchamant_bug_32573342-Insert_LAMP_New_Responsibilities_For_Responsibility_Menu_Feature
//Feature
let featureBranchName = "\n" + bugType1 + bugNumber + sprintName + comment + "\n" ;

console.log(featureBranchName);
//Hotfix branchName 

let hotfixBranchName =  "\n" + bugType2 + bugNumber + comment + "\n";

console.log(hotfixBranchName);
