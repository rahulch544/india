#!/bin/sh

#authore : rchamant

echo "What is your Name?"

read PERSON

echo "Hello $PERSON"


#variables 
# Local variables

#variable_name=variable_value
NAME="ORACLE EMPLOYEE"
readonly NAME
# NAME="RCHAMANT"

NAME1="ORACLE EMPLOYEE"
echo $NAME1

unset NAME1
echo $NAME1

# Environmental variables

# Shell variables




# #SPECIAL VARIALES STARTS WITH $

# $0 FILE NAME

# $1---$9 ARGS TO SCRIPT

# $# NO OF ARUGUMENTS

# $* "ARGS IN QUOTES"

# $@  "ARGS THAT ARE INDVIDUALLY DOUBLE QUOTES"

# $? LAST command status 0 - success 1 -failure

# $$  GIVES PROCESS ID

echo "special variable $0"

echo "special variable $1"
echo "special variable $2"
echo "special variable $#"
echo "special variable $*"
echo "special variable $$"

