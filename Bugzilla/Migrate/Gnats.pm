# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is The Bugzilla Migration Tool.
#
# The Initial Developer of the Original Code is Lambda Research
# Corporation. Portions created by the Initial Developer are Copyright
# (C) 2009 the Initial Developer. All Rights Reserved.
#
# Contributor(s): 
#   Max Kanat-Alexander <mkanat@bugzilla.org>

package Bugzilla::Migrate::Gnats;
use strict;
use base qw(Bugzilla::Migrate);

use Bugzilla::Constants;
use Bugzilla::Install::Util qw(indicate_progress);
use Bugzilla::Util qw(format_time trim generate_random_password);
use Bugzilla::Migrate::GnatsAttachment qw(ParsePatches);

use Carp qw(cluck confess);
use DateTime;
use DateTime::Format::Strptime;
use Email::Address;
use Email::MIME;
use File::Basename;
use File::Temp;
use List::MoreUtils qw(firstidx);
use List::Util qw(first);

use constant REQUIRED_MODULES => [
    {
        package => 'Email-Simple-FromHandle',
        module  => 'Email::Simple::FromHandle',
        # This version added seekable handles.
        version => 0.050,
    },
];

use constant FIELD_MAP => {
    'Number'         => 'bug_id',
    'Category'       => 'product',
    'Synopsis'       => 'short_desc',
    'Responsible'    => 'assigned_to',
    'State'          => 'bug_status',
    'Class'          => 'cf_type',
    'Classification' => '',
    'Originator'     => 'reporter',
    'Arrival-Date'   => 'creation_ts',
    'Last-Modified'  => 'delta_ts',
    'Release'        => 'version',
    'Severity'       => 'bug_severity',
    'Description'    => 'comment',
};

use constant VALUE_MAP => {
    bug_severity => {
        'serious'      => 'major',
        'cosmetic'     => 'trivial',
        'new-feature'  => 'enhancement',
        'non-critical' => 'normal',
    },
    bug_status => {
        'open'      => 'CONFIRMED',
        'analyzed'  => 'IN_PROGRESS',
        'suspended' => 'RESOLVED',
        'feedback'  => 'RESOLVED',
        'released'  => 'VERIFIED',
    },
    bug_status_resolution => {
        'feedback'  => 'FIXED',
        'released'  => 'FIXED',
        'closed'    => 'FIXED',
        'suspended' => 'LATER',
    },
    priority => {
        'medium' => 'Normal',
    },
};

use constant GNATS_CONFIG_VARS => (
    {
        name    => 'gnats_path',
        default => '/var/lib/gnats',
        desc    => <<END,
# The path to the directory that contains the GNATS database.
END
    },
    {
        name    => 'default_email_domain',
        default => 'example.com',
        desc    => <<'END',
# Some GNATS users do not have full email addresses, but Bugzilla requires
# every user to have an email address. What domain should be appended to
# usernames that don't have emails, to make them into email addresses?
# (For example, if you leave this at the default, "unknown" would become
# "unknown@example.com".)
END
    },
    {
        name    => 'component_name',
        default => 'General',
        desc    => <<'END',
# GNATS has only "Category" to classify bugs. However, Bugzilla has a
# multi-level system of Products that contain Components. When importing
# GNATS categories, they become a Product with one Component. What should
# the name of that Component be?
END
    },
    {
        name    => 'version_regex',
        default => '',
        desc    => <<'END',
# In GNATS, the "version" field can contain almost anything. However, in
# Bugzilla, it's a drop-down, so you don't want too many choices in there.
# If you specify a regular expression here, versions will be tested against
# this regular expression, and if they match, the 'capture' group will be used
# as the version value for the bug instead of the full version value specified
# in GNATS.
END
    },
    {
        name    => 'version_fallback',
        default => '',
        desc    => <<'END',
# If the "version" field fails to match version_regex, use this fallback value
# rather than the value of the field.
END
    },
    {
        name    => 'default_originator',
        default => 'gnats-admin',
        desc    => <<'END',
# Sometimes, a PR has no valid Originator, so we fall back to the From
# header of the email. If the From header also isn't a valid username
# (is just a name with spaces in it--we can't convert that to an email
# address) then this username (which can either be a GNATS username or an
# email address) will be considered to be the Originator of the PR.
END
    }
);

sub CONFIG_VARS {
    my $self = shift;
    my @vars = (GNATS_CONFIG_VARS, $self->SUPER::CONFIG_VARS);
    my $field_map = first { $_->{name} eq 'translate_fields' } @vars;
    $field_map->{default} = FIELD_MAP;
    my $value_map = first { $_->{name} eq 'translate_values' } @vars;
    $value_map->{default} = VALUE_MAP;
    return @vars;
}

# Directories that aren't projects, or that we shouldn't be parsing
use constant SKIP_DIRECTORIES => qw(
    gnats-adm
    gnats-queue
    junk.old
);

use constant NON_COMMENT_FIELDS => qw(
    Audit-Trail
    Closed-Date
    Confidential
    Unformatted
    attachments
);

# Certain fields can contain things that look like fields in them,
# because they might contain quoted emails. To avoid mis-parsing,
# we list out here the exact order of fields at the end of a PR
# and wait for the next field to consider that we actually have
# a field to parse.
use constant END_FIELD_ORDER => qw(
    Description
    How-To-Repeat
    Fix
    Release-Note
    Audit-Trail
    Unformatted
);

use constant CUSTOM_FIELDS => {
    cf_type => {
        type        => FIELD_TYPE_SINGLE_SELECT,
        description => 'Type',
    },
};

use constant FIELD_REGEX => qr/^>(\S+):\s*(.*)$/;

# Used for bugs that have no Synopsis.
use constant NO_SUBJECT => "(no subject)";

# This is the divider that GNATS uses between attachments in its database
# files. It's missign two hyphens at the beginning because MIME Emails use
# -- to start boundaries.
use constant GNATS_BOUNDARY => '----gnatsweb-attachment----';

use constant LONG_VERSION_LENGTH => 32;

my %blacklisted_bugs = (
);

#########
# Hooks #
#########

sub before_insert {
    my $self = shift;

    # gnats_id isn't a valid User::create field, and we don't need it
    # anymore now.
    delete $_->{gnats_id} foreach @{ $self->users };

    # Grab a version out of a bug for each product, so that there is a
    # valid "version" argument for Bugzilla::Product->create.
    foreach my $product (@{ $self->products }) {
        my $bug = first { $_->{product} eq $product->{name} and $_->{version} }
                        @{ $self->bugs };
        if (defined $bug) {
            $product->{version} = $bug->{version};
        }
        else {
            $product->{version} = 'unspecified';
        }
    }
}

#########
# Users #
#########

sub _read_users {
    my $self = shift;
    my $path = $self->config('gnats_path');
    my $file =  "$path/gnats-adm/responsible";
    $self->debug("Reading users from $file");
    my $default_domain = $self->config('default_email_domain');
    open(my $users_fh, '<', $file) || die "$file: $!";
    my @users;
    foreach my $line (<$users_fh>) {
        $line = trim($line);
        next if $line =~ /^#/;
        my ($id, $name, $email) = split(':', $line, 3);
        $email ||= "$id\@$default_domain";
        # We can't call our own translate_value, because that depends on
        # the existence of user_map, which doesn't exist until after
        # this method. However, we still want to translate any users found.
        $email = $self->SUPER::translate_value('user', $email);
        push(@users, { realname => $name, login_name => $email,
                       gnats_id => $id });
    }
    close($users_fh);
    return \@users;
}

sub user_map {
    my $self = shift;
    $self->{user_map} ||= { map { $_->{gnats_id} => $_->{login_name} }
                                @{ $self->users } };
    return $self->{user_map};
}

sub add_user {
    my ($self, $id, $email) = @_;
    return if defined $self->user_map->{$id};
    $self->user_map->{$id} = $email;
    push(@{ $self->users }, { login_name => $email, gnats_id => $id });
}

sub user_to_email {
    my ($self, $value) = @_;
    if (defined $self->user_map->{$value}) {
        $value = $self->user_map->{$value};
    }
    elsif ($value !~ /@/) {
        my $domain = $self->config('default_email_domain');
        # print "++> $value => $value\@$domain\n";
        confess "empty email" if ($value eq '');
        $value = "$value\@$domain";
    }
    # Normalize slightly.
    $value =~ s/[<>,]//g;
    $value =~ s/FreeBSD.org/FreeBSD.org/i;
    return $value;
}

############
# Products #
############

sub _read_products {
    my $self = shift;
    my $path = $self->config('gnats_path');
    my $file =  "$path/gnats-adm/categories";
    $self->debug("Reading categories from $file");

    open(my $categories_fh, '<', $file) || die "$file: $!";    
    my @products;
    my %product = ( name => "FreeBSD", description => "FreeBSD OS" );
    $product{components} = [];
    foreach my $line (<$categories_fh>) {
        $line = trim($line);
        next if $line =~ /^#/;
        my ($name, $description, $assigned_to, $cc) = split(':', $line, 4);
        
        my @initial_cc = split(',', $cc);
        @initial_cc = @{ $self->translate_value('user', \@initial_cc) };
        $assigned_to = $self->translate_value('user', $assigned_to);
        my %component = ( name         => $name,
                          description  => $description,
                          initialowner => $assigned_to,
                          initial_cc   => \@initial_cc );

        push @{$product{components}}, \%component;
    }
    push(@products, \%product);
    close($categories_fh);
    return \@products;
}

################
# Reading Bugs #
################

sub _read_bugs {
    my $self = shift;
    my $path = $self->config('gnats_path');
    my @directories = glob("$path/*");
    my @bugs;
    foreach my $directory (@directories) {
        next if !-d $directory;
        my $name = basename($directory);
        next if grep($_ eq $name, SKIP_DIRECTORIES);
        push(@bugs, @{ $self->_parse_project($directory) });
    }
    @bugs = sort { $a->{Number} <=> $b->{Number} } @bugs;
    return \@bugs;
}

sub _parse_project {
    my ($self, $directory) = @_;
    my @files = glob("$directory/*");

    $self->debug("Reading Project: $directory");
    # Sometimes other files get into gnats directories.
    @files = grep { (basename($_) =~ /^\d+$/) && !defined($blacklisted_bugs{basename($_)}) } @files;
    my $pr_from = $ENV{PR_FROM};
    my $pr_to = $ENV{PR_TO};
    if (defined($pr_from) && defined($pr_to)) {
        @files = grep { ($pr_from <= basename($_)) && (basename($_) < $pr_to) } @files;
    }
    my @bugs;

    my $count = 1;
    my $total = scalar @files;
    print basename($directory) . ":\n";
    foreach my $file (@files) {
        push(@bugs, $self->_parse_bug_file($file));
        if (!$self->verbose) {
            indicate_progress({ current => $count++, every => 5,
                                total => $total });
        }
    }
    return \@bugs;
}

sub _parse_bug_file {
    my ($self, $file) = @_;
    $self->debug("Reading $file");
    open(my $fh, "< :encoding(Latin1)", $file) || die "$file: $!";
    my $email = Email::Simple::FromHandle->new($fh);
    my $fields = $self->_get_gnats_field_data($email);
    # We parse attachments here instead of during translate_bug,
    # because otherwise we'd be taking up huge amounts of memory storing
    # all the raw attachment data in memory.
    my ($rest, @attachments);

    my ($fix_meta, $fix, $fix_attachments) = $self->_parse_attachments(delete $fields->{Fix}, 0);
    $fields->{Fix} = $fix if defined($fix);
    push @attachments, @$fix_attachments if defined($fix_attachments);

    my ($uf_meta, $uf, $uf_attachments) = $self->_parse_attachments(delete $fields->{Unformatted}, 0);
    # The original used ->{_add_comment}, not sure what magic made it work, or if
    # it worked at all.
    $fields->{Unformatted} .= "\n\nUnformatted:\n" . $uf if defined($uf);
    push @attachments, @$uf_attachments if defined($uf_attachments);

    $fields->{attachments} = \@attachments;
    $fields->{product} = 'FreeBSD';
    # Ignore all keywords at the mment
    $fields->{Keywords} = '';
    confess "$file" if !defined($fields->{Number});

    close($fh);
    return $fields;
}

sub _get_gnats_field_data {
    my ($self, $email) = @_;
    my ($current_field, @value_lines, %fields);
    $email->reset_handle();
    my $handle = $email->handle;
    foreach my $line (<$handle>) {
        # If this line starts a field name
        if ($line =~ FIELD_REGEX) {
            my ($new_field, $rest_of_line) = ($1, $2);
            
            # If this is one of the last few PR fields, then make sure
            # that we're getting our fields in the right order.
            my $new_field_valid = 1;
            my $search_for = $current_field || '';
            my $current_field_pos = firstidx { $_ eq $search_for }
                                             END_FIELD_ORDER;
            if ($current_field_pos > -1) {
                my $new_field_pos = firstidx { $_ eq $new_field } 
                                             END_FIELD_ORDER;
                # We accept any field, as long as it's later than this one.
                $new_field_valid = $new_field_pos > $current_field_pos ? 1 : 0;
            }
            
            if ($new_field_valid) {
                if ($current_field) {
                    $fields{$current_field} = _handle_lines(\@value_lines);
                    @value_lines = ();
                }
                $current_field = $new_field;
                $line = $rest_of_line;
            }
        }
        push(@value_lines, $line) if defined $line;
    }
    $fields{$current_field} = _handle_lines(\@value_lines);
    my $cc = $email->header('Cc');
    if ($cc) {
        $cc =~ s/; /, /g;
        $cc =~ s/;,/,/g;
        $cc =~ s/;$//g;
        $cc =~ s/,(\S)/, $1/g;
        $fields{cc} = [$cc];
    }
    
    # If the Originator is invalid and we don't have a translation for it,
    # use the From header instead.
    my $originator = $self->translate_value('reporter', $fields{Originator},
                                            { check_only => 1 });
    if ($originator !~ Bugzilla->params->{emailregexp}) {
        # We use the raw header sometimes, because it looks like "From: user"
        # which Email::Address won't parse but we can still use.
        my $address = $email->header('From');
        my ($parsed) = Email::Address->parse($address);
        if ($parsed) {
            $address = $parsed->address;
        }
        if ($address) {
            $self->debug(
                "PR $fields{Number} had an Originator that was not a valid"
                . " user ($fields{Originator}). Using From ($address)"
                . " instead.\n");
            my $address_email = $self->translate_value('reporter', $address,
                                                       { check_only => 1 });
            if ($address_email !~ Bugzilla->params->{emailregexp}) {
                $self->debug(" From was also invalid, using default_originator.\n");
                $address = $self->config('default_originator');
            }
            $fields{Originator} = $address;
        }
    }

    $self->debug(\%fields, 3);
    return \%fields;
}

sub _handle_lines {
    my ($lines) = @_;
    my $value = join('', @$lines);
    $value =~ s/\s+$//;
    return $value;
}

####################
# Translating Bugs #
####################

sub translate_bug {
    my ($self, $fields) = @_;

    my ($bug, $other_fields) = $self->SUPER::translate_bug($fields);
    print STDERR "++> " . $bug->{bug_id} . "\n";

    $bug->{attachments} = delete $other_fields->{attachments};

    if (defined $other_fields->{_add_to_comment}) {
        $bug->{comment} .= delete $other_fields->{_add_to_comment};
    }

    my ($changes, $extra_comment) =
        $self->_parse_audit_trail($bug, $other_fields->{'Audit-Trail'});

    my @comments;
    foreach my $change (@$changes) {
        if (exists $change->{comment}) {
            $change->{comment} =~ s/\s*\n\n[A-Za-z0-9\/\?\._:=-]+\s*\n$//;
            push(@comments, {
                thetext  => $change->{comment},
                who      => $change->{who},
                bug_when => $change->{bug_when} });
            delete $change->{comment};
        }
    }
    $bug->{history}  = $changes;

    $bug->{comments} = \@comments;
    
    # $bug->{component} = $self->config('component_name');
    if (!$bug->{short_desc}) {
        $bug->{short_desc} = NO_SUBJECT;
    }
    
    foreach my $attachment (@{ $bug->{attachments} || [] }) {
        $attachment->{submitter} = $bug->{reporter};
        $attachment->{creation_ts} = $bug->{creation_ts};
    }

    if (defined($extra_comment)) {
        $extra_comment = $self->_parse_extra_comment($bug, $extra_comment);	

        if (trim($extra_comment)) {
            push @${$bug->{comments}}, { thetext => $extra_comment, who => $bug->{reporter},
                          bug_when => $bug->{delta_ts} || $bug->{creation_ts} };
        }
    }

    $self->debug($bug, 3);
    return $bug;
}

sub _parse_audit_trail {
    my ($self, $bug, $audit_trail) = @_;
    return [] if !trim($audit_trail);
    $self->debug(" Parsing audit trail...", 2);
    
    if ($audit_trail !~ /^\S+-Changed-\S+:/ms) {
        # This is just a comment from the bug's creator.
        $self->debug("  Audit trail is just a comment.", 2);
        return ([], $audit_trail);
    }
    
    my (@changes, %current_data, $current_column, $on_why, %seen_columns);
    my $extra_comment = '';
    my $current_field;
    my @all_lines = split("\n", $audit_trail);
    foreach my $line (@all_lines) {
        # GNATS history looks like:
        # Status-Changed-From-To: open->closed
        # Status-Changed-By: jack
        # Status-Changed-When: Mon May 12 14:46:59 2003
        # Status-Changed-Why:
        #     This is some comment here about the change.
        if ($line =~ /^(\S+)-Changed-(\S+):(.*)/) {
            my ($field, $column, $value) = ($1, $2, $3);
            $field = ucfirst(lc($field));
            $column = lc($column);
            my $bz_field = $self->translate_field($field);
            # If it's not a field we're importing, we don't care about
            # its history.
            next if !$bz_field;
            # GNATS doesn't track values for description changes,
            # unfortunately, and that's the only information we'd be able to
            # use in Bugzilla for the audit trail on that field.
            next if $bz_field eq 'comment';
            $current_field = $bz_field if !$current_field;
            if (($bz_field ne $current_field) ||
                defined($seen_columns{$column})) {
                $self->_store_audit_change(
                    \@changes, $current_field, \%current_data);
                %current_data = ();
                %seen_columns = ();
                $current_field = $bz_field;
            }
            $seen_columns{$column} = 1;
            $value = trim($value);
            $self->debug("  $bz_field $column: $value", 3);
            if ($column eq 'from-to') {
                my ($from, $to) = split('->', $value, 2);
                # Sometimes there's just a - instead of a -> between the values.
                if (!defined($to)) {
                    ($from, $to) = split('-', $value, 2);
                }
                # Use default
                $to = 'freebsd-bugs' if (!defined($to) || $to =~ /^\s*$/);
                $from = 'freebsd-bugs' if (!defined($from) || $from =~ /^\s*$/);
                $current_data{added} = $to;
                $current_data{removed} = $from;
            }
            elsif ($column eq 'by') {
                my $email = $self->translate_value('user', $value);
                # Sometimes we hit users in the audit trail that we haven't
                # seen anywhere else.
                $current_data{who} = $email;
            }
            elsif ($column eq 'when') {
                $current_data{bug_when} = $self->parse_date($value);
            }
            if ($column eq 'why') {
                $value = '' if !defined $value;
                if (!defined($current_data{comment}))
                {
                    $current_data{comment} = "$field Changed\n";
                }
                else {
                    $current_data{comment} .= "$field Changed\n" . $current_data{comment};
                }

                my $from = $current_data{removed};
                my $to = $current_data{added};
                $current_data{comment} .= "From-To: $from" . "->" . "$to\n\n" if (defined($from) && defined($to));;

                $current_data{comment} .= $value;
                $on_why = 1;
            }
            else {
                $on_why = 0;
            }
        }
        elsif ($on_why) {
            # "Why" lines are indented four characters.
	    # They're not in the FreeBSD PR Database unfortunately -- flz
            $line =~ s/^\s{4}//;
	    # XXX - This doesn't guarantee that a full header block follows :-/
            if ($line =~ /^From:/) {
                $on_why = 0;
                $self->debug(
                    "Extra Audit-Trail line on $bug->{product} $bug->{bug_id}:"
                     . " $line\n", 2);
		$extra_comment .= "$line\n";
	    } else {
                $current_data{comment} .= "$line\n";
	    }
        }
        else {
            $self->debug(
                "Extra Audit-Trail line on $bug->{product} $bug->{bug_id}:"
                 . " $line\n", 2);
            $extra_comment .= "$line\n";
        }
    }
    $self->_store_audit_change(\@changes, $current_field, \%current_data);
    return (\@changes, $extra_comment);
}

sub _parse_extra_comment {
    my ($self, $bug, $comment) = @_;

    my $blank = 0;
    my $in_header = 1;
    my $entry = '';
    my @entries;

    my $boundary = generate_random_password(46);
    my $new_boundary;

    # print "DEBUG: Extra comment is:\n$comment";

    my @lines = split(/\n/, $comment);
    foreach my $line (@lines) {
        $line =~ s/\r$//;
        if ($line =~ /^\S/) {
            if ($blank eq 1 or $in_header ne 1) {
	        trim($entry);
                $entry =~ s/$boundary/$new_boundary/ if ($new_boundary);
                push @entries, $entry if $entry ne '';
                # print "\nDEBUG: New entry is:\n:$entry";
		$entry = '';
	    }
            $blank = 0;
            $in_header = 1;
            $entry .= "$line\n";
        } elsif ($line =~ /^\s/) {
            # Message actually starting now.
	    if ($blank eq 1 and $in_header eq 1) {
	        $in_header = 0;
	        $entry .= <<EOF;
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

EOF
            } elsif ($blank eq 1) {
                $entry .= "\n";
	    }

            # What I gather is that the boundary starts with '--' and contains
	    # basically any character but a space, including at least one non-'-'
	    # character. I should really read the MIME spec.
	    # We're only interested in keeping the last closing boundary to replace
	    # in the header we added.
	    if ($line =~ /^\s--(.+[^\s-]+)--$/) {
	        print "\nDEBUG: BOUNDARY: $1\n";
	        $new_boundary = $1;
	    }
	    $blank = 0;
	    # Some header lines are intentionally indented, don't touch these.
            $line =~ s/^\s// if ($in_header ne 1);
            $entry .= "$line\n";
        } elsif ($line =~ /^$/) {
            $blank = 1;
	    #$in_header = 0;
        } else {
            $blank = 0;
            $entry .= "$line\n";
        }
    }
    trim($entry);
    $entry =~ s/$boundary/$new_boundary/ if ($new_boundary);
    push @entries, $entry if $entry ne '';

    foreach my $entry (@entries) {
	    trim($entry);
        # print $entry;

	    my ($metadata, $rest, $attachments) = $self->_parse_attachments($entry, 1);

	    $rest =~ s/^[\s\n\r]+$//g;

            push @{$bug->{comments}}, {
                thetext  => $rest,
                who      => $metadata->{from},
                bug_when => $metadata->{date} } if $rest ne '';

	    push @{$bug->{attachments}}, 
	        @$attachments if defined($attachments);
    }
}

sub _store_audit_change {
    my ($self, $changes, $old_field, $current_data) = @_;

    $current_data->{field} = $old_field;
    $current_data->{removed} = 
        $self->translate_value($old_field, $current_data->{removed});
    $current_data->{added} =
        $self->translate_value($old_field, $current_data->{added});
    push(@$changes, { %$current_data });
}

sub _parse_attachments {
    my ($self, $text, $skipmail) = @_;
    return (undef, '', undef) if !defined($text);
    # Often the "Unformatted" section starts with stuff before
    # ----gnatsweb-attachment---- that isn't necessary.
    # XXX - Not sure if I should keep this.
    #$text =~ s/^\s*From:.+?Reply-to:[^\n]+//s;
    $text = trim($text);
    return [] if !$text;
    $self->debug('Reading attachments...', 2);
    my $boundary = generate_random_password(48);
    if ($skipmail eq 0) {
      $text = ParsePatches(\$text, $boundary);
      $text = <<END;
From: nobody <nobody\@nowhere.com>
Date: Moo. Will be overriden anyway.
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$boundary"

This is a multi-part message in MIME format.
--$boundary
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 7bit

$text
--$boundary--
END
    }
    my $email = new Email::MIME(\$text);
    my @parts = $email->parts;

    my $user;
    my $address = $email->header('From');
    my $date = $email->header('Date');
    if ($skipmail eq 1) {
	# Find out the sender.     
	if ($date eq '') {
	    # Something is really wrong here, just quit.
 	    print "WARNING: DATE: date is empty, full text is:\n$text";
	}
	if ($address eq '') {
	    # Something is really wrong here, just quit.
 	    print "WARNING: ADDRESS: address is empty, full text is:\n$text";
	}

	if ($address eq '' or $date eq '') {
	    return (undef, undef, undef);
	}

        print "DEBUG: ADDRESS (pre): $address.\n";
	if ($address !~ /\S@\S/) {
            print "WARNING: ADDRESS: Address $address doesn't contain '\@'.\n";
        } else {
	    $address =~ /\s*(\S+@\S+)\s*/;
	    $address = $1;
	    $address =~ s/[\(\)<>]//g;
        }
        print "DEBUG: ADDRESS (post): $address.\n";

        my ($parsed) = Email::Address->parse($address);
        if ($parsed) {
            $address = $parsed->address;
            $user = $address;
            $user =~ s/\@FreeBSD.org/\@FreeBSD.org/i;
            $self->add_user($user, $address);
        } else {
            print "WARNING: ADDRESS: Couldn't parse email address: $address. Defaulting to flz\@xbsd.org.";
            # $address = 'flz@xbsd.org'; 
            # $user = 'flz@xbsd.org' ;
            $address = 'gonzo@bluezbox.com'; 
            $user = 'gonzo@bluezbox.com';
        }
	print "DEBUG: USER: $user\n";

	# Deal with the date now.
	# Remove (TZ) because it usually comes with the offset anyway.
        print "DEBUG: DATE (pre): $date.\n";
	$date =~ s/\([A-Z]+\)$//;
	# Remove day of the week, serves no purpose.
	$date =~ s/^[A-Za-z]+, //;
        $date = $self->SUPER::parse_date($date);
        print "DEBUG: DATE (post): $date.\n";
    }

    my $metadata = {
        from => $address,
	date => $date,
    };

    # Remove the fake body.
    my $part1 = shift @parts;
    my $rest = '';
    if ($part1->body) {
        $self->debug(" Additional Unformatted data found");
        $self->debug($part1->body, 3);
	$rest = $part1->body;
	$rest =~ s/\n?Patch attached with submission follows:\n\n?//;
    }

    my @attachments;
    my $i = 1;
    foreach my $part (@parts) {
        trim($part->body);
	# Empty attachments can go away, thank you.
        next if ($part->body eq '');
	# We're not interested in PGP signatures or Geek Codes.
        next if ($part->body =~ /^-----BEGIN PGP SIGNATURE-----/);
        next if ($part->body =~ /^-----BEGIN GEEK CODE BLOCK-----/);
	# Skip html part, really we don't need this crap.
	next if ($part->content_type =~ m[text/html]i);
        $self->debug("  Parsing attachment #" . $i++ . ": " . $part->filename);
        my $temp_fh = File::Temp->new(DIR=>"/home/gonzo/data/tmp");
	if (!$temp_fh) {
	  print "WARNING: TMPFILE: Can't create tempfile: $!";
	  next;
        }
        print $temp_fh $part->body;
        my $content_type = $part->content_type;
        if (defined($content_type)) {
            $content_type =~ s/; name=.+$//;
        }
        else {
            if ($part->body =~ /[^[:ascii:]]/) {
                $content_type = 'application/octet-stream';
            }
            else {
                $content_type = 'text/plain';
            }
        }
	if (!(defined($part->filename)) or $part->filename eq '') {
		print "\nDESCR empty (defaulting to file.dat)!!!!\nPart body is:\n" . $part->body;
		$part->name_set('file.dat');
	}

        my $attachment = { filename    => $part->filename,
			   creation_ts => $date,
                           description => $part->filename,
                           mimetype    => $content_type,
                           data        => $temp_fh };
        $attachment->{submitter} = $user if defined($user);
        $self->debug($attachment, 3);
        push(@attachments, $attachment);
    }
    
    return ($metadata, $rest, \@attachments);
}

sub translate_value {
    my $self = shift;
    my ($field, $value, $options) = @_;
    my $original_value = $value;
    $options ||= {};

    if (!defined($value)) {
        cluck "Empty value for field '$field'";
    }

    if (!ref($value) and grep($_ eq $field, $self->USER_FIELDS)) {
        if ($value =~ /(\S+\@\S+)/) {
            $value = $1;
            $value =~ s/^<//;
            $value =~ s/>$//;
        }
        else {
            # Sometimes names have extra stuff on the end like "(Somebody's Name)"
            $value =~ s/\s+\(.+\)$//;
            # Sometimes user fields look like "(user)" instead of just "user".
            $value =~ s/^\((.+)\)$/$1/;
            $value = trim($value);
        }
    }

    if ($field eq 'version' and $value ne '') {
        my $version_re = $self->config('version_regex');
        my $version_fallback = $self->config('version_fallback');
        if ($version_re and $value =~ $version_re) {
	    $value = $+{capture};
        } elsif ($version_fallback) {
	    $value = $version_fallback;
        }
        # In the GNATS that I tested this with, there were many extremely long
        # values for "version" that caused some import problems (they were
        # longer than the max allowed version value). So if the version value
        # is longer than 32 characters, pull out the first thing that looks
        # like a version number.
	elsif (length($value) > LONG_VERSION_LENGTH) {
            # This somehow inserts a newline.
	    # $value =~ s/^.+?\b(\d[\w\.]+)\b.+$/$1/;
	    $value = substr($value, 0, LONG_VERSION_LENGTH);
	}
    }
    
    my @args = @_;
    $args[1] = $value;
    
    $value = $self->SUPER::translate_value(@args);
    return $value if ref $value;
    
    if (grep($_ eq $field, $self->USER_FIELDS)) {
        my $from_value = $value;
        $args[1] = $value;
        # If we got something new from user_to_email, do any necessary
        # translation of it.
        $value = $self->SUPER::translate_value(@args);
        if (!$options->{check_only}) {
            $value = $self->user_to_email($value);
            if ($value =~ / /) {
                confess "Space in $field $value";
            }

            $self->add_user($from_value, $value);
        }
    }
    
    return $value;
}

1;
