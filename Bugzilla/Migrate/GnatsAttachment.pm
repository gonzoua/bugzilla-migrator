#!/usr/bin/perl -Tw
#------------------------------------------------------------------------------
# Copyright (C) 2011, Shaun Amott <shaun@FreeBSD.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD: www/en/cgi/GnatsPR.pm,v 1.5 2011/08/02 13:19:32 shaun Exp $
#------------------------------------------------------------------------------

#package Bugzila::Migrate::GnatsAttachment;

use strict;

require 5.006;


#------------------------------------------------------------------------------
# Constants
#------------------------------------------------------------------------------

use constant ENCODING_BASE64 => 1;
use constant ENCODING_QP     => 2;

use constant PATCH_ANY       => 0x0001;
use constant PATCH_DIFF      => 0x0002;
use constant PATCH_UUENC     => 0x0004;
use constant PATCH_UUENC_BIN => 0x0008;
use constant PATCH_SHAR      => 0x0010;
use constant PATCH_BASE64    => 0x0020;


#------------------------------------------------------------------------------
# Func: ParsePatches()
# Desc: Parse the patches out of the given blob of text, emitting Patch and
#       Text sections as appropriate.
#
# Args: $field - Field to push new sections to.
#       \$text - Raw text
#
# Retn: n/a
#------------------------------------------------------------------------------

sub ParsePatches
{
	my ($text, $boundary) = @_;

	my $comment = '';
	my $formatted = '';

	while (my $pi = FindPatchStart($text)) {
		# Everything up to this fragment can be
		# promoted to a text section
		$comment .= substr($$text,
			             0,
				     $pi->{start},
				     '') unless $pi->{start} == 0;

		$pi->{start} = 0;

		FindPatchEnd($text, $pi);

		# Try to determine if a web/send-pr attachment
		# has another type of patch inside.
		if ($pi->{type} eq 'stdattach' or $pi->{type} eq 'webattach') {
			if (my $pi2 = FindPatchStart($text)) {
				# Upgrade to more specific type
				$pi->{type} = $pi2->{type}
					if ($pi2->{start} == 0);
			}
		}

		$pi->{name} = "file.txt" unless defined($pi->{name});

		if ($pi->{type} eq 'base64') {
			$pi->{ctype} = 'application/octet-stream';
			$pi->{encoding} = 'base64';
		} else {
			$pi->{ctype} = 'text/plain';
			$pi->{encoding} = '7bit';
		}

		$formatted .= "--$boundary\n";
		$formatted .= "Content-Type: " . $pi->{ctype} . "; name=\"" . $pi->{name} . "\"\n";
		$formatted .= "Content-Transfer-Encoding: " . $pi->{encoding} . "\n";
		$formatted .= "Content-Disposition: attachment;";
	        $formatted .= " filename=\"" .$pi->{name} . "\"\n\n"; # XXX - Generate random if undef.

	        $formatted .= substr($$text,
			       	0,
				$pi->{size},
				''); #, $pi->{name}, $pi->{type});

		$formatted .= "\n";

		$$text =~ s/^[\n\s]+//;
	}

	# Rest of the field is text
	$comment .= "\n\n$$text" if ($$text);

	$text = '';

	return $comment . $formatted;
}


#------------------------------------------------------------------------------
# Func: FindPatchStart()
# Desc: Find the beginning of the first patch inside the given text blob,
#       if there is one.
#
# Args: \$text - Raw text
#
# Retn: \%pi   - Hash of patch info (or undef):
#                  - start - Start offset of patch
#                  - type  - Type of attachment found
#                  - name  - Filename, if available
#------------------------------------------------------------------------------

sub FindPatchStart
{
	my ($text) = @_;

	# Patch from web CGI script. Characteristics:
	#   - Only ever one of them.
	#   - Appended to the end of Fix:
	#   - Blank line after header line
	#   - Could contain other types of patch (e.g. shar(1) archive)
	if ($$text =~ /^Patch attached with submission follows:$/m) { # XXX && $self->{fromwebform}) {
		my $start = $+[0]; # The newline on the above

		# Next non-blank line (i.e. start of patch)
		if ($$text =~ /\G^./m) {
			$start += $+[0]+1;
			return {start => $start, type => 'webattach'};
		}

		return undef;
	}

	# Patch from send-pr(1). Characteristics:
	#   - Has header and footer line.
	#   - Appended to the end of Fix:
	#   - User has an opportunity to edit/mangle.
	#   - Could contain other types of patch (e.g. shar(1) archive)
	if ($$text =~ /^---{1,8}\s?([A-Za-z0-9-_.,:%]+) (begins|starts) here\s?---+\n/mi) {
		my $r = {start => $-[0], type => 'stdattach', name => $1};

		# Chop header line
		substr($$text, $-[0], $+[0] - $-[0], '');

		return $r;
	}

	# Patch files from diff(1). Characteristics:
	#   - Easy to find start.
	#   - Difficult to find the end.
	$$text =~ /^((?:(?:---|\*\*\*)\ (?:\S+)\s*(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\ .*)
			|(?:(?:---|\*\*\*)\ (?:\S+)\s*(?:\d\d\d\d-\d\d-\d\d\ \d\d:\d\d:\d\d\.\d+)\ .*)
			|(diff\ -.*?\ .*?\ .*)|(Index:\ \S+)
			|(\*{3}\ \d+,\d+\ \*{4}))$/mx
		and return {start => $-[0], type => 'diff'};

	# Shell archive from shar(1)
	$$text =~ /^# This is a shell archive\.  Save it in a file, remove anything before/m
		and return {start => $-[0], type => 'shar'};

	# UUencoded file. Characteristics:
	#   - Has header and footer.
	$$text =~ /^begin \d\d\d (.*)/m
		and return {start => $-[0], type => 'uuencoded', name => $1};

	# Base64 encoded file. Characteristics:
	#   - Has header and footer.
	$$text =~ /^begin-base64 \d\d\d (.*)/m
		and return {start => $-[0], type => 'base64', name => $1};

	return undef;
}


#------------------------------------------------------------------------------
# Func: FindPatchEnd()
# Desc: Find the end of the first patch inside the given text blob, if any.
#
# Args: \$text - Raw text
#       \%pi   - Patch info hash from FindPatchStart(). We'll add more data:
#                  - size - Length of the patch.
#
# Retn: \%pi   - Same as above, except undef will be returned if no actual
#                endpoint was found (size in pi would extend to the end of the
#                text blob in this case.)
#------------------------------------------------------------------------------

sub FindPatchEnd
{
	my ($text, $pi) = @_;

	$pi->{size} = 0;

	if ($pi->{type} eq 'webattach') {
		$$text =~ /$/
			and $pi->{size} = $+[0];
	} elsif ($pi->{type} eq 'stdattach') {
		$$text =~ /^\s*---{1,8}\s?\Q$pi->{name}\E ends here\s?---+/mi
			and $pi->{size} = $-[0]-1;
		# Chop footer line
        # print "----> '$$text' <----, name = " . $pi->{name} . "\n";
        # print "----> '$+[0]' '$-[0]' <---\n",
        die "Wrong end of patch '". $pi->{name}  if (!defined($-[0]) || !defined($+[0]));
		substr($$text, $-[0], $+[0] - $-[0], '');
	} elsif ($pi->{type} eq 'diff') {
		# XXX: could do better
		$$text =~ /^$/m
			and $pi->{size} = $-[0]-1;
	} elsif ($pi->{type} eq 'shar') {
		$$text =~ /^exit$/m
			and $pi->{size} = $+[0];
	} elsif ($pi->{type} eq 'uuencoded') {
		$$text =~ /^end$/m
			and $pi->{size} = $+[0];
	} elsif ($pi->{type} eq 'base64') {
		$$text =~ /^====$/m
			and $pi->{size} = $+[0];
	}

	if ($pi->{size} == 0) {
		$pi->{size} = length $$text;
		return undef;
	}

	return $pi;
}

1;
