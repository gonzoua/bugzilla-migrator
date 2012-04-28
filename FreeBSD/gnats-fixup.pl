#!/usr/bin/perl -w

use strict;

my $junk_data = <<EOF;
From nobody  Tue Nov 17 17:41:41 1998
Message-Id: <199811180141.RAA29274\@hub.freebsd.org>
From: nobody\@junk.universe
To: freebsd-gnats-submit\@freebsd.org
Subject: this is a junk PR
X-Send-Pr-Version: www-1.0

>Number:         %PRNUM%
>Category:       junk
>Synopsis:       this is a junk PR
>Confidential:   no
>Severity:       non-critical
>Priority:       low
>Responsible:    gnats-admin
>State:          closed
>Quarter:        
>Keywords:       
>Date-Required:  
>Class:          sw-bug
>Submitter-Id:   current-users
>Arrival-Date:   %DATE%
>Closed-Date:    %DATE%
>Last-Modified:  %DATE%
>Originator:     Joe Spammer
>Release:        
>Organization:
Junk Universe
>Environment:
>Description:
This is a stub for a bogus or non-existent PR
the original can be found here:
http://www.freebsd.org/cgi/query-pr.cgi?pr=%PRNUM%
>How-To-Repeat:

>Fix:

>Release-Note:
>Audit-Trail:
State-Changed-From-To: open->closed 
State-Changed-By: gonzo 
State-Changed-When: %DATE%
State-Changed-Why:  
Bogus PR. 
>Unformatted:
EOF

my $gnats_dir = "/usr/gnats";

undef $/;

if (-d "$gnats_dir/junk.old" ) {
    print "Cowardly refuses to continue fixup: junk.old directory exists\n";
    exit 1;
}

# RGet the list of all available PRs
opendir CURDIR, $gnats_dir;
my @dirs = grep {!/^\./} readdir(CURDIR);
closedir(CURDIR);

my @prs;

foreach my $d (@dirs) {
    next unless -d $d;
    opendir PRS, $d;
    my @files = grep {/^\d+$/} readdir(PRS);
    closedir(PRS);
    push @prs, @files;
}

@prs = sort {$a <=> $b} @prs;

# Empty junk folder and recreate 
rename "$gnats_dir/junk", "$gnats_dir/junk.old" or die "Failed to rename junk to junk.old";
mkdir "$gnats_dir/junk";

# Pass 1
# check missing PRs and create stubs with the date of the last
# available PR
my $i = 0;
while ($i < $#prs) {
    if ($prs[$i] + 1 != $prs[$i+1]) {
        my $date_from = get_date($prs[$i]);
        for (my $x = $prs[$i] + 1; $x < $prs[$i+1]; $x+=1) {
            print "-> Resurrecting PR junk/$x, date: date_from\n";
            generate_junk($x, $date_from);
        }
        my $date_to = get_date($prs[$i+1]);
    }
    $i += 1;   
}


# Pass 2 
# Replace all existing junk PRs with stubs in order to reduce
# amount of enthorpy in the universe
opendir PRS, "$gnats_dir/junk.old";
my @junk_files  = grep {/^\d+$/} readdir(PRS);
closedir(PRS);

foreach my $j (@junk_files) {
    open F, "< $gnats_dir/junk.old/$j";
    my $tmp = <F>;
    close F;
    $tmp =~ m/^>Arrival-Date:\s+(.*?)$/ms;
    my $date = $1;
    die "no date for PR $j" if !defined($date);
    generate_junk($j, $date);
}

#
# Helper routines
#

sub get_date
{
    my $pr = shift;
     use File::Glob ':glob';
    my $file = bsd_glob("$gnats_dir/*/$pr");
    die "glob failed for */$pr" if (!defined($file));
    open F, "< $file";
    my $tmp = <F>;
    close F;
    $tmp =~ m/^>Arrival-Date:\s+(.*?)$/ms;
    die "no date in $pr" if (!defined($1));
    return $1;
}

sub generate_junk
{
    my ($pr, $date) = @_;
    my $t = $junk_data;
    $t =~ s/%PRNUM%/$pr/g;
    $t =~ s/%DATE%/$date/g;
    open F, "> $gnats_dir/junk/$pr";
    print F $t;
    close F;
}
