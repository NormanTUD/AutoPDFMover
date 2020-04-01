#!/usr/bin/perl

use strict;
use warnings;
use autodie;
use Digest::MD5 qw/md5_hex/;
use Carp qw/cluck/;
use List::Util qw(sum);
use Time::HiRes qw/gettimeofday/;
use File::Basename;
use File::Copy;
use Term::ANSIColor;
use Data::Dumper;
use Digest::MD5::File qw(file_md5_hex);
use open ':std', ':encoding(UTF-8)';
use utf8;
use Memoize;
memoize '_file_md5_hex';

sub red ($);
sub ongreen ($);
sub onyellow ($);
sub debug (@);
sub debug_copy ($$);

my %options = (
	debug => 0,
	splitfile => 1,
	done => './done',
	tmp => './tmp',
	todo => './todo',
	global_tmp => '/tmp/',
	manual => './manual',
	rmtmp => 1,
	crop => '', #'4000x240+260+2200',
	randomorder => 0,
	regex => qr#((?:Herr|Frau)\s+(?:(?:.*\h.*)|(?:.*[\r\n].*)))#,
	exitaftern => 0
);

analyze_args(@ARGV);

create_paths();

main();

sub main {
	if($options{splitfile}) {
		my @files_todo = ();
		while (my $file = <$options{todo}/*.pdf>) {
			push @files_todo, $file;
		}

		foreach my $todo (@files_todo) {
			my $filewithoutfolderandextension = $todo;
			$filewithoutfolderandextension =~ s#$options{todo}##;
			$filewithoutfolderandextension =~ s#\.pdf##;
			my $command = qq(gs -o $options{tmp}/$filewithoutfolderandextension-%04d.pdf -sDEVICE=pdfwrite $todo);
			debug_system($command);
		}
	}

	my @tmp_files = ();
	while (my $file = <$options{tmp}/*.pdf>) {
		if(!defined(file_already_moved($file))) {
			push @tmp_files, $file;
		}
	}

	my @times = ();
	my $i = 0;

	my $number_of_items = scalar(@tmp_files);
	if($options{exitaftern}) {
		$number_of_items = $options{exitaftern};
	}

	if($options{randomorder}) {
		@tmp_files = sort { rand() <=> rand() } @tmp_files;
	}

	foreach my $file (@tmp_files) {
		my $starttime = gettimeofday();
		$i++;
		my $timer = sprintf("%d of %d, %.2f percent", $i, $number_of_items, ($i / $number_of_items * 100));
		onyellow $timer;
		if(@times) {
			my $avg_time = mean(@times);
			my $resttime = $avg_time * (($number_of_items - $i) + 1);
			
			my $rest_time = sprintf("Avg. time: %s, rest time: %s", 
				humanreadabletime($avg_time), 
				humanreadabletime($resttime));
			onyellow $rest_time;
		}

		debug "\n\n\nNow working on $file";

		my $file_already_moved = file_already_moved($file, 1);
		if (!defined($file_already_moved)) {
			my $name = get_name($file);

			if($name) {
				my $tocopy_name = "$options{done}/$name.pdf";
				debug_copy $file, $tocopy_name;
			} else {
				red "ERROR: $file did not match $options{regex}!";
				debug_copy $file, "$options{manual}/".get_filename_from_path($file);
			}
		} else {
			ongreen "File $file already exists in $options{done} ($file_already_moved)";
		}
		my $endtime = gettimeofday();
		push @times, $endtime - $starttime;

		if($options{exitaftern} && $i >= $options{exitaftern}) {
			red "Exiting because limit --exitaftern=$options{exitaftern} has been reached";
			exit;
		}
	}
}

sub get_name {
	my $filename = shift;
	debug "get_name($filename)";

	my $rand_path = get_tmp_folder($filename)."/";


	my $tmp_file = get_random_tmp_file('.pdf', $rand_path);
	debug_copy $filename, $tmp_file;

	my $ocred_file = '';
	$ocred_file = ocr_pdf($tmp_file, $options{crop});

	my $text = get_text_from_pdf($ocred_file);

	if ($text =~ m#$options{regex}#) {
		my $name = $1;
		$name =~ s#\R# #g;
		$name =~ s#\s{2,}# #g;

		$name =~ s#\x{0131}#i#g; # dotless i
		$name =~ s#kEberhard#Eberhard#;
		$name =~ s#\s*-\s*$##;
		$name =~ s#HeinzjJürgen#Heinz-Jürgen#;

		onyellow "-----> $name";
		return $name;
	} else {
		red "$ocred_file does not contain $options{regex}";
		red "CONTENTS: >>>";
		red $text;
		red "<<<";
		return '';
	}
}

sub mean {
	my $ret = 0;
	eval {
		$ret = sum(@_) / @_;
	};

	if($@) {
		cluck("Error: $@");
	}
	return $ret;
}

sub debug_qx {
	my $command = shift;

	debug $command;
	if(wantarray()) {
		my @output = qx($command);
		return @output;
	} else {
		my $output = qx($command);
		return $output;
	}
}

sub read_file {
	my $file = shift;

	my $contents = '';

	open my $fh, '<', $file;
	while (<$fh>) {
		$contents .= $_;
	}
	close $fh;

	return $contents;
}

sub write_file {
	my ($file, $contents) = @_;
	debug "write_file($file, ...)";

	open my $fh, '>', $file or die $!;
	print $fh $contents;
	close $fh;
}

sub get_random_tmp_file {
	my $extension = shift // '';
	my $path = shift // '/tmp/';
	my $rand = rand();
	$rand =~ s#0\.##g;

	while (-e $path.$rand.$extension) {
		$rand = rand();
		$rand =~ s#0\.##g;
	}

	return "$path$rand$extension";
}

sub get_text_from_pdf {
	my $file = shift;
	my $cache = shift // 1;
	debug "get_text_from_pdf($file, $cache)";

	my $file_md5 = md5_hex($file);
	my $filepath_md5 = "$options{global_tmp}/$file_md5";
	
	if($cache && -e $filepath_md5) {
		debug "OK!!! Got text for $file in $filepath_md5!!!";
		return read_file($filepath_md5);
	} else {
		my $pdftotext = debug_qx(qq#pdftotext "$file" - | egrep -v "^\\s*\$"#);
		if(length($pdftotext) >= 10) {
			write_file($filepath_md5, $pdftotext);
			return $pdftotext;
		}

		my $textfile = get_random_tmp_file('.txt');

		debug_system(qq#gs -sDEVICE=txtwrite -o "$textfile" "$file"#);

		if(!-e $textfile) {
			return '';
		} else {
			my $c = read_file($textfile);
			if(length($textfile) >= 10) {
				write_file($filepath_md5, $c);
			}
			return $c;
		}
	}
}

sub get_tmp_folder {
	my $file = shift;

	my $md5 = md5_hex($file);
	my $md5tmp = "$options{global_tmp}/data_$md5";
	mkdir $md5tmp unless -d $md5tmp;

	return $md5tmp;
}

sub split_pdf {
	my $file = shift;
	my $path = shift;
	debug "split_pdf($file, $path)";

	debug_system(qq#gs -o $path/%04d.pdf -sDEVICE=pdfwrite "$file"#);

	opendir my $DIR, $path or die "Can't open $path: $!";
	my @pdfs = grep { /\.(?:pdf)$/i } readdir $DIR;
	closedir $DIR;

	return @pdfs;
}

sub create_jpgs_from_pdfs {
	my $path = shift;
	debug "create_jpgs_from_pdfs($path, \@pdfs)";
	my @pdfs = @_;

	foreach my $pdf (@pdfs) {
		my $dpi = 800;
		my $number = remove_file_ending($pdf);
		$number = add_leading_zeroes($number);
		debug_system(qq#cd $path; gs -dNOPAUSE -dBATCH -sDEVICE=jpeg -r$dpi -dJPEGQ=100 -sOutputFile="$number.jpg" "$pdf"#);
	}

	opendir my $DIR, $path or die "Can't open $path: $!";
	my @images = grep { /\d+\.(?:jpg)$/i } readdir $DIR;
	closedir $DIR;

	return @images;
}

sub merge_pdfs {
	my $path = shift;
	my $file = shift;
	debug "merge_pdfs($path, $file)";

	opendir my $DIR, $path or die "Can't open $path: $!";
	my @pdfs = grep { length($_) == 9 && /0\d+\.(?:pdf)$/i } readdir $DIR;
	closedir $DIR;

	debug_system(qq#cd $path; pdftk "#.join('" "', sort grep { $_ ne get_filename_from_path($file) } @pdfs).qq#" cat output "#.get_filename_from_path($file).qq#"#);

	my $pdf_file = "$path/".get_filename_from_path($file);

	return $pdf_file;
}

sub ocr_pdf {
	my $file = shift;
	my $crop = shift // 0;
	debug "ocr_pdf($file, crop = $crop)";

	my $rand_path = get_tmp_folder($file);

	my @pdfs = split_pdf($file, $rand_path);
	my @images = create_jpgs_from_pdfs($rand_path, @pdfs);

	my $language = 'deu';

	if (@images) {
		foreach my $jpegpath (@images) {
			next if -e remove_file_ending($jpegpath).".pdf";

			if($crop) {
				my $crop_command = qq#cd $rand_path; convert -crop $crop $jpegpath $jpegpath#;
				debug_system($crop_command);
			}

			my $ocr_command = "cd $rand_path; tesseract -l ".$language.' '.$jpegpath.' '.remove_file_ending($jpegpath)." pdf; ";
			if($options{rmtmp}) {
				$ocr_command .= "rm -f $jpegpath";
			}
			debug_system($ocr_command);
		}
	} else {
		red "NO IMAGES IN $rand_path!!!";
	}

	my $pdf_file = merge_pdfs($rand_path, $file);

	return $pdf_file;
}

sub remove_file_ending {
	my $filename = shift;
	$filename =~ s#\.[a-z0-9]+$##gi;
	return $filename;
}

sub add_leading_zeroes {
	my $number = shift;
	return $number if length($number) >= 5;
	while (length($number) != 5) {
		$number = "0$number";
	}
	return $number;
}

sub get_filename_from_path {
	my $filepath = shift;

	my ($name, $path, $suffix) = fileparse($filepath);

	return $name;
}

sub debug_system {
	my $command = shift;

	debug $command;
	return system($command);
}

sub humanreadabletime {
	my $hourz = int($_[0] / 3600);
	my $leftover = $_[0] % 3600;
	my $minz = int($leftover / 60);
	my $secz = int($leftover % 60);

	return sprintf ("%02d:%02d:%02d", $hourz,$minz,$secz)
}


sub red ($) {
	my $arg = shift;
	print color("red").$arg.color("reset")."\n";
}

sub onyellow ($) {
	my $arg = shift;
	print color("on_yellow blue").$arg.color("reset")."\n";
}

sub ongreen ($) {
	my $arg = shift;
	print color("on_green blue").$arg.color("reset")."\n";
}

sub debug (@) {
	return unless $options{debug};
	foreach (@_) {
		warn color("green")."$_".color("reset")."\n";
	}
}

sub help {
	print <<EOF;
This script scans PDF files for a regex and then moves them accordingly to the regex.
Default regex: $options{regex}

OPTIONS

	--debug				Enables debug output
	--splitfile=[01]		Splits files (not needed when ran before, otherwise automatically enabled)
	--tmp=/path			Path to tmp (where splitted files go)
	--todo=/path			Path to files that should be sorted
	--manual=/path			Path where files that could not be assigned go
	--crop=4000x350+400+2200	Crop files before doing OCR to speed up OCR (ImageMagick crop)
	--rmtmp=[01]			Removes temporary files after moving the file (automatically enabled)
	--exitaftern=N			Exit after n documents (for debugging)
	--randomorder=[01]		Work on files in random order
	--regex=(Herr|Frau\s.*)		Set regex to search for
	--help				This help
EOF
}

sub analyze_args {
	my @args = @_;

	foreach (@args) {
		if(m#^--debug$#) {
			$options{debug} = 1;
		} elsif (m#^--splitfile=([01])$#) {
			$options{splitfile} = $1;
		} elsif (m#^--tmp=(.*)$#) {
			$options{tmp} = $1;
		} elsif (m#^--done=(.*)$#) {
			$options{done} = $1;
		} elsif (m#^--todo=(.*)$#) {
			$options{todo} = $1;
		} elsif (m#^--manual=(.*)$#) {
			$options{manual} = $1;
		} elsif (m#^--randomorder=([01])$#) {
			$options{randomorder} = $1;
		} elsif (m#^--crop=(.*)$#) {
			$options{crop} = $1;
		} elsif (m#^--rmtmp=([01])$#) {
			$options{rmtmp} = $1;
		} elsif (m#^--regex=(.*)$#) {
			$options{regex} = qr/$1/;
		} elsif (m#^--exitaftern=(\d*)$#) {
			$options{exitaftern} = $1;
		} elsif (m#^--help$#) {
			help();
			exit(0);
		} else {
			red "Unknown parameter $_";
			help();
			exit(1);
		}
	}
}

sub create_paths {
	foreach (qw/done tmp todo manual/) {
		unless (-d $options{$_}) {
			mkdir $options{$_} or die $!;
		}
	}
}

sub debug_copy ($$) {
	my ($from, $to) = @_;
	if(-e $to) {
		my $i = 0;

		my $noending = remove_file_ending($to)."-$i.pdf";

		while (-e $noending) {
			$noending = remove_file_ending($to)."-$i.pdf";
			$i++;
		}

		$to = $noending;
	}
	my $command = qq#cp "$from" "$to"#;
	debug $command;
	if(system($command)) {
		die "ERROR: $!";
	} else {
		debug "OK: $command, exited with $?";
		debug(map { chomp $_; $_ } debug_qx(qq#md5sum "$from" "$to"#));
	}
}

sub _file_md5_hex {
	my $arg = shift;
	if(-e $arg) {
		return file_md5_hex($arg);
	} else {
		die "ERROR: $arg not found!";
	}
}

sub file_already_moved {
	my $filename = shift;
	my $force = shift // 0;
	debug "file_already_moved($filename)";

	if(-e $filename) {
		my $this_file_md5 = file_md5_hex($filename);

		opendir my $DIR, $options{done} or die "Can't open $options{done}$!";
		my @pdfs = map { "$options{done}/$_" } readdir $DIR;
		closedir $DIR;


		foreach my $donefile (@pdfs) {
			next if -d $donefile;
			my $this_done_file_md5 = undef;
			if(!$force) {
				$this_done_file_md5 = _file_md5_hex($donefile);
			} else {
				$this_done_file_md5 = file_md5_hex($donefile);
			}

			if($this_done_file_md5 eq $this_file_md5) {
				return $donefile;
			}
		}

		return undef;
	} else {
		return undef;
	}
}
