#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use lib $Bin.'/lib/perl5';

use 5.012; # so readdir assigns to $_ in a lone while test

use Getopt::Long;
use Config::Simple;
use XML::RSS;
use MIME::Types;

my $projPath;
my $debug = 0;
my $test = 0;
my $config;

my $sampleConfig = <<EOF;
title="Podcast Title"
link="http://blah.com"
description="Podcast Description"
extensions = "flv", "mp4", "mp3"
httpbase="http://server/test-podcast"
EOF

GetOptions ("path=s" => \$projPath,
	"debug" => \$debug,
	"test" => \$test);

usage() if !defined $projPath;

main();
exit 0;

sub usage{
	die <<EOF;
Usage:
	$0 -path /path/to/my/videos_or_audio_podcasts [-verbose] [-debug] [-test]

-test	run the program without writing the xml file (output to console)
-debug	enable debugging output

EOF
}

sub loadConfig{
	my $configFile = $projPath.'/config.ini';
	
	print "Checking if $configFile is readable.$/" if $debug;
	die "Can't read config file $configFile!$/ Here is a sample config:$/$sampleConfig" if !-r $configFile;
	
	my %tempConfig;
	print "Loading config file $configFile.$/" if $debug;
	Config::Simple->import_from($configFile, \%tempConfig);
	
	print "Checking if needed variables exist in the config file.$/" if $debug;
	if(
		defined $tempConfig{'default.title'} &&
		defined $tempConfig{'default.link'} &&
		defined $tempConfig{'default.description'} &&
		defined $tempConfig{'default.extensions'} &&
		defined $tempConfig{'default.httpbase'}
	   ){
		print "All config variables exist.$/" if $debug;
	}
	else{
		die <<EOF;
Can't find all of the needed variables in the config file.
The config file should look like this:
--cut--
$sampleConfig
--cut--

EOF
	}
	$config = \%tempConfig;
}

sub main{
	print "Running in test mode, no xml file will be written.$/" if $debug && $test;
	
	loadConfig();
	
	print "Generating RSS.$/" if $debug;
	my $rss = XML::RSS->new(version => '2.0', encode_output => 0);

	$rss->channel(
		title => $config->{'default.title'},
		link => $config->{'default.link'},
		description => $config->{'default.description'},
		);
	if( defined $config->{'default.image'} ){
		print "Found image variable in the config files, adding image tag to rss.$/" if $debug;
		$rss->image(
			title => $config->{'default.title'},
			url => $config->{'default.image'},
			link => $config->{'default.link'},
		);
	}
	
	print "Searching for ".join(', ', @{$config->{'default.extensions'}})." in $projPath.$/" if $debug;
	
	# generating regex for extensions match
	my $extensionsMatch = join('|', @{$config->{'default.extensions'}});
	# compiling regex for extensions match
	$extensionsMatch = qr/($extensionsMatch)$/i;
	
	# hash for later sorting and adding to rss
	# this step is needed to sort items by modification date
	my %items;
	
	opendir(my $dh, $projPath) || die;
    while(readdir $dh) {
		my $fullPath = $projPath.'/'.$_;
		# we don't need dirs
		next if -d $fullPath;
		# we don't need empty files
		next if -z $fullPath;
		# if we got here then the file should be usable
		
		if( /$extensionsMatch/i ){
			my $timeStamp = (stat($fullPath))[9];
			my $inode = (stat($fullPath))[1];
			# the hash key is a combination of unix time stamp
			# and an inode number for files which are created in the same second
			$items{ $timeStamp.$inode } = $_;
		}
    }
    closedir $dh;
	
	# object for detecting mime types
	my $mimetypes = MIME::Types->new;
	# going through the sorted keys of array and adding items to rss
	foreach my $key ( sort {$b <=> $a} keys(%items) ){
		my $filename = $items{$key};
		my ($fileExtension) = ($filename =~ /\.([\w\d]+)$/);
		my $fileMimeType = $mimetypes->mimeTypeOf($filename)->type();
		
		print "Adding $filename.$/" if $debug;
		$rss->add_item(
			title => $config->{'default.title'}.' - '.$filename,
			link => $config->{'default.httpbase'}.'/'.$filename,
			enclosure   => { url => $config->{'default.httpbase'}.'/'.$filename, type=>$fileMimeType },
			description => $filename,
		);
	}
	
	if($test){
		print $rss->as_string;
		exit 0;
	}
	
	my $outFile = $projPath.'/rss.xml';
	print "Saving xml to $outFile$/" if $debug;
	#because save function of XML::RSS writes doesn't get well with UTF-8 we will write file using perl
	open(my $fh, ">", $outFile);
	print $fh $rss->as_string;
	close($fh);
}

