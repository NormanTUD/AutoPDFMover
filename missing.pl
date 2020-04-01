use strict;
use warnings;
use Data::Dumper;

my $diffcommand = qq(diff -u donemd5_nf tmpmd5_nf | grep -E "^\\+");
update_diff();

while (my @lines = grep { $_ !~ m#\@# } map { chomp; s#^\+##g; $_ } qx($diffcommand)) {
	foreach my $line (@lines) {
		next if $line =~ m#^\+#;

		my $file = get_tmp_filename($line);

		my $tmpfile = "/tmp/".rand();
		while (-e $tmpfile) {
			$tmpfile = "/tmp/".rand();
		}

		system(qq#evince "$file"#);

		system(qq#touch $tmpfile#);

		system("vim $tmpfile");

		my $newname = `cat $tmpfile`;
		chomp $newname;
		my $filename = "done/$newname.pdf";

		my $i = 0;
		while (-e $filename) {
			$filename = "done/$newname-$i.pdf";
			$i++;
		}

		print(qq#cp "$file" "$filename"\n#);
		system(qq#cp "$file" "$filename"#);	
		update_diff();
	}

	update_diff();
}

sub get_tmp_filename {
	my $line = shift;
	my $command = qq#cat tmpmd5 | grep $line | sed -e 's/.* //'#;
	my $ret = qx($command);
	chomp $ret;
	return $ret;
}

sub update_diff {
	qx(md5sum done/* > donemd5);
	qx(cat donemd5 | sed -e 's/ .*//' > donemd5_nf);
	qx(sort -o donemd5_nf donemd5_nf)
}
