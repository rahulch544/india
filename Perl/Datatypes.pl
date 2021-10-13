$string = "Hello world";

print "$string \n";

$integer = 9394;

print "$integer \n";

@array = ($string,$string." hello");

print "$array[0] \n";
print "$array[1] \n";

$aarray = [$string,$string." tanker"];
print "$aarray \n";
print "$aarray->[0] \n";
print "$aarray->[1] \n";
print "$$aarray[0] \n";
print "${$aarray}[0] \n";
print "Dummy value \n";
print ${aarray}->[0];
print "\n";


%hash = ('John Paul', 45, Lisa, 30, Kumar, 40);

print %hash;print "\n";

%hash_1 = ('John Paul', 45, 'Lisa', 30, 'Kumar', 40);

print %hash_1;print "\n";

%hash_2 = ('John Paul' => 45, 'Lisa' => 30, 'Kumar' => 40);

print %hash_2;print "\n";

%hash_3 = (-JohnPaul => 45, -Lisa => 30, -Kumar => 40);

print %hash_3;print "\n";

@array = @hash_3{-JohnPaul, -Lisa};

print "Array : @array\n";

@ages = values %hash_3;

print join(" ",@ages);print "\n";

@keys = keys %hash_3;
$size = @keys;
print "1 - Hash size:  is $size\n";

delete $hash_3{-Kumar};
@keys = keys %hash_3;
$size = @keys;
print "3 - Hash size:  is $size\n";
print join(" ",@keys);print "\n";


$a_hash = {'John Paul', 45, Lisa, 30, Kumar, 40};
print "anonmous hash array \n";
print $a_hash;print "\n";
print %$a_hash;print "\n";

print "anonmous hash array \n";
print %{$a_hash};print "\n";

print "\n\n";

print $a_hash->{Lisa};print "\n";
print $$a_hash{Lisa};print "\n";
print ${$a_hash}{Lisa};print "\n";


