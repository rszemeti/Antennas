#!/usr/bin/perl

use strict;
use warnings;

# Copyright Robin Szemeti G1YFG 2023

# based on work done by Leif Asbrink SM5BSZ

package BoomCorrection;

use Data::Dumper qw/Dumper/;

# Constants from PAREQ.INC
my $CVEL = 299792458;  # Speed of light in m/s

# to calculate freespace frequency
my $ZER_LEN = 0.0547;
my $ZER_DIAM = 0.733;
my $ZER_CONST = 0.13405;

# end corrections
my $FAR_FAC = 23;
my $FAR_DIST_EXP = -0.887;

# convert sq boom to equivalent round boom
my $SQUARE_ADD = 0.18; # add 18% to round boo diameter to use square tube

# and here the fun starts
my $H12 = -0.008620;
my $H20 = 0.02285;
my $H21 = 4.78;
my $H22 = 1.135;
my $H23 = 0.0204;
my $H31 = -41.75;
my $H32 = 1.5193;
my $H33 = -36.9;
my $H41 = 0.16;


sub new {

   my($class)=shift;
   
   my($params) = shift;
   
   my($self)={};
   
   if(ref($params) eq "HASH"){
    $self = {
      _freq => $params->{freq},
      _ityp => $params->{boomType},
      _d => $params->{boomSize},
      _th => $params->{wallThick},
      _h => $params->{holeSize},
      _ed => $params->{eleDia},
     };
     
   }else{
     $self = {
      _freq => $params,
      _ityp => shift,
      _d => shift,
      _th => shift,
      _h => shift,
      _ed => shift,
     };
   }



    $self->{_warn_errors} = 0;
    $self->{_db} = $self->{_d} * (1 + $self->{_ityp} * $SQUARE_ADD);

    # scaling factor for frequency and m to mm
    $self->{_df} = $self->{_freq} / 144000;

    # scale input values, in metres
    $self->{_ds} = $self->{_df} * $self->{_d};   # boom dia
    $self->{_dbs} = $self->{_df} * $self->{_db};   # boom dia compensated for shape
    $self->{_ths} = $self->{_df} * $self->{_th}; # hole size
    $self->{_eds} = $self->{_df} * $self->{_ed}; # ele diameter
    $self->{_hs} = $self->{_df} * $self->{_h};   # hole size

    bless $self, $class;
    return $self;
 }

 sub warnErrors{
    my($self)=shift;
    $self->{_warn_errors} = 1;
 }
 
sub ignoreErrors{
    my($self)=shift;
    $self->{_warn_errors} = 2;
 }

 sub checkHeader{
    my($self)=@_;

    # Check for errors in header
    if ($self->{_ds} > 0.09) {
        print STDERR "ERR    BOOM TUBE OUTER DIAMETER TOO LARGE $self->{_d}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_ds} < 0.015) {
        print STDERR "ERR    BOOM TUBE DIAMETER TOO SMALL $self->{_d}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_eds} > 0.014) {
        print STDERR "ERR    ELEMENT TOO THICK $self->{_ed}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_eds} < 0.0028) {
        print STDERR "ERR    ELEMENT TOO THIN $self->{_ed}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_d} / $self->{_ed} < 1.9) {
        print STDERR "ERR   ELEMENT TOO THICK FOR BOOM TUBE $self->{_ed} $self->{_d}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_d} / $self->{_h} < 1.7) {
        print STDERR "ERR   HOLE TOO BIG FOR BOOM TUBE $self->{_h} $self->{_d}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($self->{_hs} - $self->{_eds} < 0.0003) {
        print STDERR "ERR   HOLE TOO SMALL FOR ELEMENT $self->{_h} $self->{_ed}\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }  
}


sub correctElement{
    my($self)=shift;
    my($X, $Z) = @_;

    my $XS = $self->{_df} * $X;   # ele length    
    my($FQ) = $self->freespace_freq($XS);

    if ($FQ < 125000000) {
        print STDERR  "ERR    ELEMENT TOO LONG $X\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }
    if ($FQ > 160000000) {
        print STDERR "ERR     ELEMENT TOO SHORT $X\n" unless ($self->{_warn_errors} > 1);
        die unless $self->{_warn_errors};
    }

    my($DLEN) = $self->boom_corr($XS);
    
    # if the element position from end of boom is specified ... 
    if ($Z > 0) {
        my $wl_in_freespace = $CVEL / $FQ;
        my $DW = $self->{_ds} / $wl_in_freespace;
        my $ZS = $Z * $self->{_df};

        # must be at least 1 boom dia from the end.
        if ($Z < $self->{_d}) {
            print STDERR "ERR   BOOM END TOO CLOSE (CORRECTION NOT YET KNOWN) $Z\n";
            die unless $self->{_warn_errors};
        }

        my $ZW = $ZS / $wl_in_freespace;

        # takes 
        #       $DW, boom diameter, in wavelengths
        #       $ZW, distance to end in wavelengths
        # returns 
        #       $freqChange is the difference in frequency of the element caused by it being close to a boom end
        #       a boom end rather than in in infinite boom

        my($freqChange)=$self->endcut($DW, $ZW);

        # Find the length adjustment that would cause the same frequency shift.
        # It is going to need to be longer, so start off 1mm shorter and work up.

        my $DX = 0.001;
        my ($X1, $X2) = ($XS, $XS + $DX);

        # $F1 is the freq shift with our current length (initally zero)
        # $F2 is the freq shift with our x+dx length
        my ($F1, $F2) = (0, $self->freespace_freq($X2) - $FQ);

        # adjust DX until we get within 0.1mm
        while (abs($DX) > 0.0001) {

            # calc slope in Hz per m
            my $DER = ($F2 - $F1) / $DX;


            # store current length and freq
            ($X2, $F2) = ($X1, $F1);

            # calculate a new length based on a linear interpolation 
            $X1 = $X1 + ($freqChange - $F1) / $DER;
            $F1 = $self->freespace_freq($X1) - $FQ;

            $DX = $X2 - $X1;
        }
        my($endCorrection) = $X1 - $XS;

        $DLEN = $DLEN + $endCorrection;
    }

    # de-scale the correction
    $DLEN = $DLEN / $self->{_df};

    return $DLEN;
}

# estimates the amount to be added to the element to compensate for "through boom" loss of effective length
# this works with scaled paramters relative to 144mhz
sub boom_corr {
    my ($self, $xl) = @_;

    my $result = (sqrt($self->{_dbs}) + $H12 / sqrt($self->{_dbs}));
    
    $result *= ($H20 + $H21 * $self->{_ths} + $H22 * ($self->{_hs} - $self->{_eds}) + $H23 * ($self->{_eds} / $self->{_dbs}));
    
    $result *= (1 + $H31 * ($self->{_hs} - $self->{_eds}) + $H32 * sqrt($self->{_ds} - 2 * $self->{_ths}) + $H33 * ($self->{_eds} * $self->{_ths} / $self->{_dbs}));
    $result *= ($H41 + $xl);

    return $result;
}

# $dB, boom diameter in wavelengths
# $dist, distance to end in wavelengths
# return frequency shift in Hz compared to 
sub endcut {
    my ($self,$d, $dist, $ityp) = @_;
    # calculate effectice boom diameter $dm depending if it is round or sqaure
    my $db = $d * (1 + $self->{_ityp} * $SQUARE_ADD);
    my($ze) = $FAR_FAC * $db**2 * $dist**$FAR_DIST_EXP;
    $ze *= 1000000;
    return $ze;
}

# given an element length and diameter (in metres)
# returns its freespace self resonant freq in Hz
sub freespace_freq {
    my ($self, $x) = @_;
    my $effLength = (1 - $ZER_LEN) * $x + $ZER_DIAM * sqrt($self->{_eds}) + $ZER_CONST;
    my($freq) = $CVEL / (2* $effLength);
    return $freq;
}

package BoomData;



