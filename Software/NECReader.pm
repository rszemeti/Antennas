#!/usr/bin/perl

use warnings;
use strict;

package NecReader;


sub new{
     my($class)=shift;

    my $self = {
      _file => shift,
    };

    if (-e $self->{_file} && -r $self->{_file} && -f $self->{_file}) {
      
    } else {
      die "File ".$self->{_file}." is not readable."
    }
   
    bless $self, $class;
    return $self;
}

sub parse{
    my($self)=shift;
  
    my($wires)=[];
    my($ex,$fr,$srcFreq);
    

    open(my $inNec, '<', $self->{_file}) or die "Couldn't open $self->{_file} : $!";

    while(<$inNec>){
      #print $_;
      chomp;
      my($line)=$_;
      if($line =~ /^GW/){
         # wire
         my(@w)=split(/\s+/,$line);
         push(@{$wires},{ tag=>$w[1],segs=>$w[2], x1=>$w[3], y1=>$w[4], z1=>$w[5],x2=>$w[6], y2=>$w[7], z2=>$w[8], rad =>$w[9], scale=>1.000});
      }elsif($line =~/^EX/){
        $ex = $line;
      }elsif($line =~/^FR/){
        $fr = $line;
        my(@f)=split(/\s+/,$line);
        $self->{_srcFreq} = $f[5];
      }
    }
    
    $self->{_wires}=$wires;
    
    close $inNec;
    
}

sub getWires{
  my($self)=shift;
  return $self->{_wires};
}

sub getSrcFreq{
  my($self)=shift;
  return $self->{srcFreq};
}

return 1;

