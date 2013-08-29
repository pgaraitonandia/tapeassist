#!/usr/bin/env perl
# 
# Fri Aug 23 2013
# Written by Pablo Garaitonandia for Penn State University
# This program will minimize the amount of files needed to 
# back up to tape for the zimbra back ups. Directories with 
# the zimbraID of each user will be put in a tar archive.
# This will reduce the amount of files to back up, should
# you chose to delete the directories after they have been
# archived 
#
#
# See bottom of the file for instructions

use strict;
use warnings;
use Getopt::Long;
use File::Path qw(remove_tree);
use Sys::Syslog;
use Sys::Syslog qw(:standard :macros setlogsock);
use vars qw($name $fd $path);
use POSIX qw(:fcntl_h);

sub usage;
sub conf_present($);
sub slog($$$);


#
# SUBROUTINES
#


sub slog($$$) 
	{
		# Print to syslog and/or STDOUT
		my ( $priority, $msg, $print ) = @_;
		my $prio;
		my $txt;

		if ($priority == 0) 
			{
				$prio = 'info';
				$txt = "$prio" . ": " . "$msg" ;
			} 
		else 
			{
				$prio = 'err';
				$txt = "$prio" . ": " . "$msg" ;
			}

		setlogsock('unix');
		syslog($prio, $txt);

		if ($print =~ /y/) 
			{
				print "$msg\n";
			}
	}

sub conf_present($) 
	{
		# Check for existance of attributes in config file.
		my ($type) = @_;
		my $msg = "$type attribute not present in config file.";
		slog(1 , $msg, "y");
		exit 2; 
	}

sub usage 
	{
		# usage
		my ($umsg) = (@_);

		$umsg && print STDERR "\nINCORRECT USAGE: $umsg\n\n";
		my $msg =  "INCORRECT USAGE";
		slog(1, $msg, "n");
		print STDERR <<USAGE;

	tape_assist.pl	-f config_file 

	Where:
	-h: help.
	-f: location of config file.

	CONFIG FILE PARAMETER EXAMPLES
	BASEDIR=/opt/zimbra/backup			Base directory of zimbra backups
	COMPRESS=YES or NO				Compress the UID directories
	DELETE=YES or NO				Delete UID directories after archive 
USAGE

		exit (1);
	}

#
# MAIN
#


$name = "tapeassist"; 
openlog($name, "ndelay,pid", "local2");

eval 
	{
		my $id=getpwuid($<);
		my $help=0;
		my $cfg=0;
		my %info=();
		my $dir="";
		my $compress;
		my $del;
		my $tar;
		my $suffix;
		my @base;
		my @parent;
		my @full;
		my @params=("BASEDIR" , "COMPRESS" , "DELETE");

		# Ensure user is zimbra.
		chomp $id;
		if ($id ne "zimbra")
			{
				my $msg =  "Must be run as zimbra user.";
				slog(1, $msg, "y"); 
				exit (1);
			}

		# Ensure proper use.
		GetOptions(
				'h|help' => \$help,
				'f|cfg=s'=> \$cfg, ) or usage(1);


		if ($help)
			{
				usage();
			} 
		elsif ($cfg eq 0)
			{
				usage(1);
			}

		# -r  File is readable by effective uid/gid.
		# -f  File is a plain file.
		# -e  File exists.
		unless ((-e $cfg) and (-f $cfg) and (-r $cfg))
			{
				my $msg =  "Please ensure your config file is exists and is readable.";
				slog(1, $msg, "y");
				usage(1);
			}

		# Get name of config file to craft name of lock file
		my @lfile = split(/\//, "$cfg" );
		my $lock = pop @lfile;
		$path = "/var/lock/$lock" . ".lock";

		# Ensure that only one process with the same config is running.
		if  (-e $path)
			{
				my $msg = "Invalid request: Previous tapeassist may still in progress," . 
				" or lock file may need to be deleted:" . " $path";
				slog(1, $msg, "y");
				die(" \n");
			}
		# Create lock file
		$fd = POSIX::open($path, O_CREAT|O_EXCL|O_WRONLY, 0644) ;
			if (!defined($fd)) 
				{
					die "Unable to create lock file. \n";
				}


		# get config file and stuff it into an array
		open(FILE, $cfg) || die("\nCould not open config file!\n");
		my @lines=<FILE>;
		chomp(@lines);
		close(FILE);

		foreach my $lines (@lines) 
			{
				# Get rid of what we do not want. 
				# commented lines get undefined.
				if ($lines =~ /#/ )
					{
						$lines = undef;
					}
			}

		# Get rid of blank lines
		@lines = grep { defined } (@lines);


		# Get the param and the values from the 
		# config file and put them in a hash.
		foreach	 my $lines (@lines) 
			{
				%info = map {split(/=/)} @lines;
			}


		# Check to see that parameters needed are present 
		# in config file. 
		foreach my $params (@params)
			{ 
				if (grep { /$params/ } %info) 
					{ 
						# prints the parameter and the corresponding
						# value from the hash.
						my $msg =  "PARAMETER SET: $params = $info{$params}"; 
						slog(0, $msg, "y");
					} 
				else 
					{
						my $msg =  "MISSING PARAMETER IN CONFIG FILE: $params";
						slog(1, $msg, "y");
						usage(1);
					}
			}

		# Check to see if the param for BASEDIR is a directory
		# and is a zimbra back up directory
		unless (-d $info{BASEDIR})
			{
				my $msg =  "BASEDIR: $info{BASEDIR} does not exist.";
				slog(1, $msg, "y");
				exit (1);
			} 
		elsif (! -d "$info{BASEDIR}/sessions" ) 
			{
				my $msg	 = "$info{BASEDIR}" . "/sessions does not exist.";
				slog(1, $msg, "y");
				$msg  = "BASEDIR needs to be pointed to a zimbra back up directory.";
				slog(1, $msg, "y");
				usage(1);
			} 
		elsif (! -e "$info{BASEDIR}/accounts.xml" ) 
			{
				print "\n" . "$info{BASEDIR}" . "/accounts.xml does not exist. \n";
				print "BASEDIR needs to be pointed to a zimbra back up directory. \n";
				my $msg = "$info{BASEDIR}" . "/accounts.xml does not exist.";
				slog(1, $msg, "y");
				$msg  = "BASEDIR needs to be pointed to a zimbra back up directory.";
				slog(1, $msg, "y");
				usage(1);
			} 
		elsif (length($info{BASEDIR}) < 2 )
			{
				my $msg = "$info{BASEDIR}" . ": BASEDIR incorrect.";
				slog(1, $msg, "y");
				$msg  = "BASEDIR needs to be pointed to a zimbra back up directory.";
				slog(1, $msg, "y");
				usage(1);
			} 
		else 
			{
				$dir = "$info{BASEDIR}/sessions";
				my $msg =  "$dir is the base directory.";
				slog(0, $msg, "n");
			}

		unless (($info{COMPRESS} =~ /yes/i) or ($info{COMPRESS} =~ /no/i))
			{
				my $msg =  "Incorrect paramater for COMPRESS: $info{COMPRESS}";
				slog(1, $msg, "y");
				$msg = "Please Specify either \"COMPRESS=YES\" or \"COMPRESS=NO\" ";
				slog(1, $msg, "y");
				usage(1);
			} 
		else 
			{
				$compress = $info{COMPRESS};
				my $msg =  "Compression value set = " . "$compress";
				slog(0, $msg, "n");
			}

		unless (($info{DELETE} =~ /yes/i) or ($info{DELETE} =~ /no/i))
			{
				my $msg = "Incorrect paramater for DELETE: $info{DELETE} ";
				slog(1, $msg, "y");
				print "Please Specify either \"DELETE=YES\" or \"DELETE=NO\"   \n";
				usage(1);
			} 
		else 
			{
				$del = $info{DELETE};
				my $msg =  "Deletion value set = " . "$del";
				slog(0, $msg, "n");
			}
		# Creating tar arguments and file suffix
		if ($compress =~ /yes/i) 
			{
				$tar = "czf";
				$suffix = "tgz"
			} 
		else 
			{
				$tar = "cf";
				$suffix = "tar"
			}


	# Allow for maipulation of directories in the back up.
	@base = grep {-d} (glob ("$dir/*"));
	#@parent = grep {-d} (map { (glob ("$_/*/*/*"));} (@base));
	@parent = grep {-d} (map { (glob ("$_/accounts/*/*"));} (@base));
	@full = grep {-d} (map { (glob ("$_/*"));} (@parent));

	foreach my $parent (@parent)
		{
			my $targdir;

			if (grep(/$parent/, @full))
				{
					($targdir)	= (grep(/$parent/, @full));
					my $msg = "Target Dir= " . "$targdir";
					slog(0, $msg, "n");
					$msg = "Parent Dir = " . "$parent";
					slog(0, $msg, "n");
				} 
			else 
				{
					next;
				}

			if (-e "$targdir")
				{
					my @userdir = split(/\//, $targdir) ;
					my $userid =  pop @userdir;
					my @files;
					my $msg = sprintf("Creating Archive: $parent/$userid.$suffix");
					slog(0, $msg, "n");

				if ((-e "$parent/$userid.$suffix") and ($del =~ /yes/i))
					{
						my $msg = "Archive already exists. Deleting $parent/$userid";
						slog(0, $msg, "y");
						remove_tree($targdir);
						next;
					}

				elsif ((-e "$parent/$userid.$suffix") and ($del =~ /no/i))
					{
						my $msg = "Archive already exists.";
						slog(0, $msg, "n");
						next;
					}

				# Create tar archives
				system("/bin/tar $tar $parent/$userid.$suffix -C $parent $userid  > /dev/null 2>&1") == 0
						or die "Could not create $parent/$userid.$suffix";

				if ($? == 0)
					{
						my $msg = "Succesfully created $parent/$userid.$suffix";
						slog(0, $msg, "y");
					}

				elsif ($? == -1) 
					{
						my $msg = sprintf("failed to execute: $!");
						slog(1, $msg, "y");
						next;
					} 
				elsif ($? & 127) 
					{
						my $msg = sprintf("child died with signal %d, %s coredump", ($? & 127),	 ($? & 128) ? 'with' : 'without');
						slog(1, $msg, "y");
						next;
					} 
				else 
					{
						my $msg = sprintf("child exited with value %d\n", $? >> 8);
						slog(1, $msg, "y");
						next;
					}

				if ((-e "$parent/$userid.$suffix") and ($del =~ /yes/i))
					{
						my $msg = "Deleting $parent/$userid";
						slog(0, $msg, "y");
						remove_tree($targdir);
					}
				}

		}
			# Close and remove lock file
			POSIX::close($fd);
			unlink($path);
			my $msg = "Done.";
			slog(0, $msg, "y");
};

if ($@) 
	{
		print STDERR ($@);
		my $msg = "($@)" ;
		slog(1, $msg, "n");
		exit(3);
	}

closelog();



__END__


INSTALLATION

1) Put the following line in your (r)syslog.conf and restart (r)syslog.

local2.*                -/var/log/tapeassist.log

2) Create a config file with the following parameters set

# CONFIG FILE PARAMS
BASEDIR=/opt/zimbra/backup	Base directory of zimbra backups.
COMPRESS=YES or NO		Compress the user directories.
DELETE=YES or NO		Delete ZimbraID directories after being archived.

3) Add the zimbra user to the lock group in /etc/group

4) Add the following line to the list of files in /etc/logrotate.d/syslog

/var/log/tapeassist.log

5) Put the script in the zimbra crontab to execute when you like or execute 
by hand.

00 6,23 * * * /usr/local/bin/tape_assist.pl -f /etc/tapeassist/tapeassist.cfg > /dev/null 2>&1






