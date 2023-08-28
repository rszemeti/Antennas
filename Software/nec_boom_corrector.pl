#!/usr/bin/perl

use warnings;
use strict;

use lib ".";
use NecReader;
use BoomCorrection;

use Data::Dumper qw/Dumper/;

my($file)= shift @ARGV;

my($startDist)=40.0;
my($boomLength)=2500.0;
my($sbc)=2.92;

my($rdr)= new NecReader($file);
$rdr->parse();

my($bc)= new BoomCorrection(
  {freq =>1296,
   boomType=>1, 
   boomSize => 15.9,
   wallThick => 1.6,
   holeSize => 5.8,
   eleDia => 4.0}
);

$bc->warnErrors();
$bc->checkHeader();
$bc->ignoreErrors();

foreach my $wire (@{$rdr->getWires()}){
  my($len)=  abs($wire->{y1}-$wire->{y2}) *1000;
  if($len>0){
    my($corr)=$bc->correctElement($len,nearestEnd($startDist,$boomLength,$wire->{x1}*1000));
    printf("%s, %0.2f, %0.2f, %0.2f, %0.2f\n",$wire->{tag},$wire->{x1}*1000+$startDist,$len,$corr,$len+$corr+$sbc);
  }
}

sub nearestEnd{
  my($start, $length, $x)=@_;
  
  $x = $x +$start;
  my($mid)=$length/2;
  
  if($x > $mid){
    return $length - $x;
  }else{
    return $x;
  }
}

exit 1;