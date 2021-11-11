# operators

#loops

for var in 1 2 3 4
do
	echo $var
done



# while command
# do
# 	statement

# done

a=0
while [ $a -lt 10 ]
do 
	echo $a
	a==`expr $a+1`
done	


until [ ! $a -lt 10]
do 
	echo $a
		a==`expr $a+1`

	if [ $a -eq 5]
	then
		break
	fi		
	if [ $a -eq 3]
	then
		continue
	fi		
	echo "found number"
done

