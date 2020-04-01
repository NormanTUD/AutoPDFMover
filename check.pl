use strict;
use warnings;
use IO::Prompter;
use Data::Dumper;

my $onlylist = 0;
if(@ARGV >= 1 && $ARGV[0] eq '--list') {
	$onlylist = 1;
}

my $letter = qr/[\wäöüÄÖÜß-]/;
my $lettersmall = qr/[\wäöüß-]/;

my $ignore = '';
if(-e "ignorelist") {
	$ignore = '('.join(')|(?:', map { chomp $_; $_; } qx(cat ignorelist)).')';
}

my @list = ();

if(!$onlylist) {
	print "PRESS 'y' to correct or 'i' to ignore\n\n";
}

while (my $file = <done/*.pdf>) {
	my $name = $file;
	$name =~ s#^done/##g;
	$name =~ s#\.pdf$##g;

	if(length($ignore) == 0 || $name !~ m#$ignore#) {
		if (
			$name =~ m#^(Herr|Frau)\s$letter+(\s$letter+)+# &&
			# HeinzjJürgen
			$name !~ m#[äöüßa-z][A-Z]# &&
			$name !~ m#\s[äöüßa-z]# &&
			$name !~ m#[!:]# &&
			$name !~ m#(?=-)\d# &&
			$name !~ m#ii# &&
			$name !~ m# -\s*# &&
			$name !~ m#\.#
		) {
		} else {
			print $name;
			if($onlylist) {
				print "\n";
			}

			push @list, $name;

			if(!$onlylist) {
				my $correct = prompt " - Correct?";
				if($correct =~ m#[yj]#) {
					my $tmpfile = "/tmp/".rand();
					while (-e $tmpfile) {
						$tmpfile = "/tmp/".rand();
					}

					system(qq#evince "$file"#);

					system(qq#echo "$name" > $tmpfile#);

					system("vim $tmpfile");

					my $newname = `cat $tmpfile`;
					chomp $newname;
					my $filename = "done/$newname.pdf";

					my $i = 0;
					while (-e $filename) {
						$filename = "done/$newname-$i.pdf";
					}

					print(qq#mv "$file" "$filename"\n#);
					system(qq#mv "$file" "$filename"#);
				} elsif ($correct =~ m#i#) {
					open my $fh, '>>', 'ignorelist';
					print $fh "$name\n";
					close $fh;
				}
			}
		}
	}
}

print "Number of founds: ".scalar(@list)."\n";
