#! /usr/bin/perl
use strict;
use warnings;
use utf8;
use DateTime::Format::Strptime;
use Date::Parse;

my @engine =
(
  {
    locale     => "af_ZA",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%a %b %e %H:%M:%S %Z %Y",
  },
  {
    locale     => "am_ET",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%a %b %e %H:%M:%S %Z %Y",
  },
  {
    locale     => "be_BY",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "bg_BG",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "ca_ES",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%A, %e de %B de %Y, %H:%M:%S %Z",
  },
  {
    locale     => "cs_CZ",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e. %B %Y %H:%M:%S %Z",
  },
  {
    locale     => "da_DK",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "de_AT",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "de_CH",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "de_DE",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "el_GR",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "en_AU",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "en_CA",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "en_GB",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    # Alternative format used in email headers, optional day name was removed.
    locale     => "en_GB",
    pattern    => '%d %B %Y %T %z',
    pattern_tz => '%d %B %Y %T %Z',
  },
  {
    locale     => "en_IE",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "en_NZ",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "en_US",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%a %b %e %H:%M:%S %Z %Y",
  },
  {
    # Alternative format, after replacing ambiguous TZ with the time offset.
    locale     => "en_US",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%a %b %e %H:%M:%S %z %Y",
  },
  {
    locale     => "es_ES",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%A, %e de %B de %Y, %H:%M:%S %Z",
  },
  {
    locale     => "et_EE",
    pattern    => "%a, %d. %b %Y. %T",
    pattern_tz => "%A, %d. %B %Y. %T %Z",
  },
  {
    locale     => "eu_ES",
    pattern    => "%Y - %b - %e %a %H:%M:%S",
    pattern_tz => "%Y(e)ko %B-ren %ea, %H:%M:%S %Z",
  },
  {
    locale     => "fi_FI",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "fr_BE",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "fr_CA",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "fr_CH",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "fr_FR",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "he_IL",
    pattern    => "%Z %H:%M:%S %Y %b %d %a",
    pattern_tz => "%a %b %e %H:%M:%S %Z %Y",
  },
  {
    locale     => "hr_HR",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "hu_HU",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%Y %b %e %a %H:%M:%S %Z",
  },
  {
    locale     => "hy_AM",
    pattern    => "%A, %e %B %Y \x{56B}. %H:%M:%S",
    pattern_tz => "%A, %e %B %Y \x{569}. %H:%M:%S (%Z)",
  },
  {
    locale     => "is_IS",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "it_CH",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "it_IT",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "ja_JP",
    pattern    => "%a %m/%e %T %Y",
    pattern_tz => "%Y\x{5E74} %B%e\x{65E5} %A %H\x{6642}%M\x{5206}%S\x{79D2} %Z",
  },
  {
    locale     => "kk_KZ",
    pattern    => "%A, %e %B %Y \x{436}. %H:%M:%S",
    pattern_tz => "%A, %e %B %Y \x{436}. %H:%M:%S (%Z)",
  },
  {
    locale     => "ko_KR",
    pattern    => "%x %A %H\x{C2DC} %M\x{BD84} %S\x{CD08}",
    pattern_tz => "%c %Z",
  },
  {
    locale     => "lt_LT",
    pattern    => "%a %b %e %H:%M:%S %Y",
    pattern_tz => "%A, %Y m. %B %e d. %T %Z",
  },
  {
    locale     => "lv_LV",
    pattern    => "%e. %b, %Y. gads %H:%M:%S",
    pattern_tz => "%A, %Y. gada %e. %B %T %Z",
  },
  {
    locale     => "mn_MN",
    pattern    => "%Y \x{43E}\x{43D}\x{44B} %B \x{441}\x{430}\x{440}\x{44B}\x{43D} %e, %A \x{433}\x{430}\x{440}\x{430}\x{433}, %H:%M:%S ",
    pattern_tz => "%Y \x{43E}\x{43D}\x{44B} %B \x{441}\x{430}\x{440}\x{44B}\x{43D} %e, %A \x{433}\x{430}\x{440}\x{430}\x{433}, %H:%M:%S",
  },
  {
    locale     => "nb_NO",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "nl_BE",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "nl_NL",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "nn_NO",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "pl_PL",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "pt_BR",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "pt_PT",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "ro_RO",
    pattern    => "%a %e %b %Y %H:%M:%S",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "ru_RU",
    pattern    => "%A, %e %B %Y \x{433}. %H:%M:%S",
    pattern_tz => "%A, %e %B %Y \x{433}. %H:%M:%S (%Z)",
  },
  {
    locale     => "sk_SK",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e. %B %Y %H:%M:%S %Z",
  },
  {
    locale     => "sl_SI",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "sr_YU",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "sv_SE",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "tr_TR",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%e %b %Y %a %Z %H:%M:%S",
  },
  {
    locale     => "uk_UA",
    pattern    => "%a %e %b %H:%M:%S %Y",
    pattern_tz => "%a %e %b %Y %H:%M:%S %Z",
  },
  {
    locale     => "zh_CN",
    pattern    => "%a %b/%e %T %Y",
    pattern_tz => "%Y\x{5E74}%b\x{6708}%e\x{65E5} %A %H\x{65F6}%M\x{5206}%S\x{79D2} %Z",
  },
  {
    locale     => "zh_HK",
    pattern    => "%a %b/%e %T %Y",
    pattern_tz => "%Y\x{5E74}%b\x{6708}%e\x{65E5} %A %H\x{6642}%M\x{5206}%S\x{79D2} %Z",
  },
  {
    locale     => "zh_TW",
    pattern    => "%a %b/%e %T %Y",
    pattern_tz => "%Y\x{5E74}%b\x{6708}%e\x{65E5} %A %H\x{6642}%M\x{5206}%S\x{79D2} %Z",
  },
)
;
for my $e (@engine) {
	$e->{parser} = DateTime::Format::Strptime->new(
		pattern => $e->{pattern},
		locale => $e->{locale});
	$e->{parser_tz} = DateTime::Format::Strptime->new(
		pattern => $e->{pattern_tz},
		locale => $e->{locale});
	$e->{count} = 0;
	print "$e->{locale}: parser problem\n" unless $e->{parser};
	print "$e->{locale}: parser_tz problem\n" unless $e->{parser_tz};
}

sub guess_date
{
	my $d = shift;

	# Some timezones are ambiguous. Assume what most people would assume.
	$d =~ s/ MET/ CET/;
	$d =~ s/ MEDT/ CEST/;
	$d =~ s/ CET DST/ CEST/;
	$d =~ s/ PST/ -0800/;
	$d =~ s/ EST/ -0500/;
	$d =~ s/ CDT/ -0500/;

	my $k = 0;
	my $dt;
	my $l;
	for my $e (@engine) {
		$dt = $e->{parser}->parse_datetime($d);
		if ($dt) {
			$l = $e->{locale};
			$e->{count}++;
			last;
		}
		$dt = $e->{parser_tz}->parse_datetime($d);
		if ($dt) {
			$l = $e->{locale};
			$e->{count}++;
			last;
		}
		$k++;
	}
	if ($dt && $k > 0 && $engine[$k]->{count} > $engine[$k-1]->{count}) {
		@engine = sort { $b->{count} <=> $a->{count} } @engine;
	}
    if (!$dt) {
        my $epoch = str2time($d);
        $dt = DateTime->from_epoch( epoch => $epoch ) if ($epoch);
    }
	return wantarray ? ($dt,$l) : $dt;
}

1;
