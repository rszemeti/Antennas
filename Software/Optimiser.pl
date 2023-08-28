#!/usr/bin/perl

use warnings;
use strict;

use File::Spec;
use Data::Dumper qw/Dumper/;
use Cwd;

use Math::Complex;

my($necDir) = 'C:\\4nec2\\';

my($infile)=shift @ARGV;
my($destFreq)=shift @ARGV;

die "No destination frequency given" unless defined($destFreq) && $destFreq > 0;

open(my $inNec,"<$infile") or die $!;

my(@wires,$ex,$fr,$srcFreq);

while(<$inNec>){
  #print $_;
  chomp;
  my($line)=$_;
  if($line =~ /^GW/){
     # wire
     my(@w)=split(/\s+/,$line);
     $wires[$w[1]]= { tag=>$w[1],segs=>$w[2], x1=>$w[3], y1=>$w[4], z1=>$w[5],x2=>$w[6], y2=>$w[7], z2=>$w[8], rad =>$w[9], scale=>1.000};
  }elsif($line =~/^EX/){
    $ex = $line;
  }elsif($line =~/^FR/){
    $fr = $line;
    my(@f)=split(/\s+/,$line);
    $srcFreq = $f[5];
  }
}

my($scale)=$destFreq/$srcFreq;
my($lambda) = 299792458/($srcFreq*1000000);

print "Source Frequency: $srcFreq\n";
print "Destination Frequency: $destFreq\n";
print "Scale: $scale\n";

chdir("$necDir\\exe\\") or die "Failed to open NEC directory $necDir: $!\n";
writeCommandFile("optimiser.nec","optimiser.out");

my($result)= analyse();

print "Initial fwd gain: ".$result->{fwd}."\n";
print "Initial rev gain: ".$result->{rev}."\n";


    my($wireNumb)=$#wires;
    while($wireNumb > 4){
      optimiseWire($wireNumb,0);
      $wireNumb--;
    }

    $wireNumb=$#wires;
    while($wireNumb > 4){
      optimiseWire($wireNumb,1);
      $wireNumb--;
    }


optimiseWire(1,0);


optimiseWireSwr(5);
optimiseBentDE([2,3,4],0);

optimiseWireSwr(32);
optimiseBentDE([2,3,4],1);

$result = analyse();

print "Final fwd gain: ".$result->{fwd}."\n";
print "Final rev gain: ".$result->{rev}."\n";
print "Final swr: ".$result->{swr}."\n";


writeOutfile(\@wires,$fr,$ex,"optimised.nec",1/$scale);

exit 1;

sub optimiseBentDE{
    my($wa,$pass)=@_;
    foreach my $wireNumb (@{$wa}){
      if($pass==0){
        my($targetRad) = $wires[$wireNumb]->{rad}*$scale;
        print "Adjusting wire $wireNumb from ".2*$wires[$wireNumb]->{rad}." to ".2*$targetRad." diameter\n";
        setWireRadius($wireNumb,$targetRad);
      }
    }
    
    optimiseDriverPos($wa->[0],$wa->[1],$wa->[2],-1);
    optimiseDriverBend($wa->[0],$wa->[2],-0.5);
    optimiseDriverPos($wa->[0],$wa->[1],$wa->[2],-1);
    optimiseDriverBend($wa->[0],$wa->[2],-0.5);
    optimiseDriverPos($wa->[0],$wa->[1],$wa->[2],1);
    optimiseDriverBend($wa->[0],$wa->[2],0.5);
    optimiseDriverPos($wa->[0],$wa->[1],$wa->[2],-0.5);
    optimiseDriverBend($wa->[0],$wa->[2],-0.5);
    optimiseDriverPos($wa->[0],$wa->[1],$wa->[2],0.5);
}

sub adjustSekLength{
  my($wireNumb,$origRad)=@_;
  my($len)=abs($wires[$wireNumb]->{y2}-$wires[$wireNumb]->{y1});
  print "orig length: $len\n";
  print "orig length: $origRad\n";
  print "$lambda\n";
  my($react)=getReactance($len,$origRad);
  print "reactance is $react\n";
  print "new rad: ".$wires[$wireNumb]->{rad}."\n";
  my($newLen)=reactToLen($react,$wires[$wireNumb]->{rad});
  $wires[$wireNumb]->{y1} = $newLen/-2;
  $wires[$wireNumb]->{y2} = $newLen/2;
}

sub reactToLen{
  my($x,$rad)=@_;
  my($newLen)=((($x-40.0)/(430.3*(log($lambda/$rad)/log(10))-320))+1)*($lambda/2);
  return $newLen;
}

sub getReactance{
  my($len,$rad)=@_;
  my($x) = (430.3 * log($lambda/$rad)/log(10) - 320)*((2*$len/$lambda) -1) + 40;
  return $x;
}

sub optimiseWire{
    my($wireNumb,$pass)=@_;
    my($targetRad) = $wires[$wireNumb]->{rad}*$scale;

     if($pass==0){
         print "Adjusting wire $wireNumb from ".2*$wires[$wireNumb]->{rad}." to ".2*$targetRad." diameter\n";
        my($origRad)=$wires[$wireNumb]->{rad};
        setWireRadius($wireNumb,$targetRad);
        adjustSekLength($wireNumb,$origRad);
     }else{
       optimiseWireByParam($wireNumb,0,0.25,$pass);
     }

     #optimiseWireByParam($wireNumb,0,-0.25,$pass);
     #optimiseWireByParam($wireNumb,0,0.5,$pass);
}

sub optimiseWireSwr{
    my($wireNumb)=@_;

     optimiseWireSwrByParam($wireNumb,0,-0.25);
     #optimiseWireByParam($wireNumb,0,0.5,$pass);
}

sub optimiseWireByParam{
     my($wireNumb,$dx,$dy,$pass,$weights)=@_;

     my($init) = analyse();
     my($initDiff)=abs($init->{fwd} - $result->{fwd});

     #adjust element length until we get the same gain
     my($adjusted)=0;
     while(1){
       my($opt)=analyse();
       print "Wire $wireNumb, length ".($wires[$wireNumb]->{y2} - $wires[$wireNumb]->{y1})."\n";
       print "Modified fwd gain: ".$opt->{fwd}."\n";
       print "Modified rev gain: ".$opt->{rev}."\n";
       my($diff)=abs($opt->{fwd} - $result->{fwd});
       my($optFbr) = $opt->{fwd} - $opt->{rev};
       if(  ($opt->{fwd} < $init->{fwd}) 
            || (($pass==0)&&($opt->{fwd} >= 19.7))
            || (($pass==0)&&($opt->{rev} > $init->{rev})) 
            || (($pass==2)&&($opt->{swr} > $init->{swr}))){
         # backstep
         if($adjusted){
            adjustWire($wireNumb,$dx*-1,$dy*-1);
         }
         last;
       }
       $init = $opt;
       adjustWire($wireNumb,$dx,$dy);
       $adjusted=1;
     }
}

sub optimiseWireSwrByParam{
     my($wireNumb,$dx,$dy)=@_;

     my($init) = analyse();
     #adjust element length until we get the same gain
     my($adjusted)=0;
     while(1){
       my($opt)=analyse();
       print "Wire $wireNumb, length ".($wires[$wireNumb]->{y2} - $wires[$wireNumb]->{y1})."\n";
       print "Modified swr: ".$opt->{swr}."\n";
       if( $opt->{swr} > $init->{swr} ){
         # backstep
         if($adjusted){
            adjustWire($wireNumb,$dx*-1,$dy*-1);
         }
         last;
       }
       $init = $opt;
       adjustWire($wireNumb,$dx,$dy);
       $adjusted=1;
     }
}

sub optimiseDriverBend{
     my($wire1,$wire2,$dx)=@_;

     my($init) = analyse();

     #adjust element length until we get the same gain
     my($adjusted)=0;
     while(1){
       my($opt)=analyse();
       print "Modified fwd gain: ".$opt->{fwd}."\n";
       print "Modified rev gain: ".$opt->{rev}."\n";
       print "Modified real: ".$opt->{impedance}->{real}."\n";
       print "Modified imag: ".$opt->{impedance}->{imag}."\n";
       print "Modified swr: ".$opt->{swr}."\n";
       if( $opt->{swr} > $init->{swr} ){
         # backstep
         if($adjusted){
            $wires[$wire1]->{x1} -= $dx/1000;
            $wires[$wire2]->{x2} -= $dx/1000;
         }
         last;
       }
       $init = $opt;
       $wires[$wire1]->{x1} += $dx/1000;
       $wires[$wire2]->{x2} += $dx/1000;
       $adjusted=1;
     }
}

sub optimiseDriverPos{
     my($wire1,$wire2,$wire3,$dx)=@_;
     $dx = $dx/1000;

     my($init) = analyse();

     #adjust element length until we get the same gain
     my($adjusted)=0;
     while(1){
       my($opt)=analyse();
       print "Modified fwd gain: ".$opt->{fwd}."\n";
       print "Modified rev gain: ".$opt->{rev}."\n";
       print "Modified real: ".$opt->{impedance}->{real}."\n";
       print "Modified imag: ".$opt->{impedance}->{imag}."\n";
       print "Modified swr: ".$opt->{swr}."\n";
       if( $opt->{swr} > $init->{swr} ){
         # backstep
         if($adjusted){
            $wires[$wire1]->{x1} -= $dx;
            $wires[$wire1]->{x2} -= $dx;
            $wires[$wire2]->{x1} -= $dx;
            $wires[$wire2]->{x2} -= $dx;
            $wires[$wire3]->{x1} -= $dx;
            $wires[$wire3]->{x2} -= $dx;
         }
         last;
       }
       $init = $opt;
       $wires[$wire1]->{x1} += $dx;
       $wires[$wire1]->{x2} += $dx;
       $wires[$wire2]->{x1} += $dx;
       $wires[$wire2]->{x2} += $dx;
       $wires[$wire3]->{x1} += $dx;
       $wires[$wire3]->{x2} += $dx;
       $adjusted=1;
     }
}

#sub quality{
#  my($r,$weights)=@_;
#  return $r->{fwd}*$weights->{fwd}+$r->{rev}*$weights->{rev}+$r-}{swr}*$weights->{swr};
# }

sub analyse{
 writeOutfile(\@wires,$fr,$ex,"optimiser.nec",1);
 runNec();
 my($opt) = parseOutfile("optimiser.out");
 return $opt;
}

sub adjustWire{
  my($n,$dx,$dy)=@_;
  $wires[$n]->{x1} += $dx/1000;
  $wires[$n]->{x2} += $dx/1000;
  $wires[$n]->{y1} -= $dy/2000;
  $wires[$n]->{y2} += $dy/2000;
}

sub setWireRadius{
  my($n,$rad)=@_;
  $wires[$n]->{rad} = $rad;
}



sub calculateSwr {
    my ($real, $imag) = @_;

    my $characteristic_impedance = 50; # Characteristic impedance of the system
    my $z = Math::Complex->make($real, $imag);
    my $z0 = $characteristic_impedance;
    my $reflection_coefficient = ($z - $z0) / ($z + $z0);
    my $reflection_magnitude = abs($reflection_coefficient);
    my $swr = (1 + $reflection_magnitude) / (1 - $reflection_magnitude);
    return $swr;
}

# performs an initial scaling on the wire, we will tweak this!
sub scaleWire{
  my($n,$scale)=@_;
  my($origDia)= $wires[$n]->{rad}*2;
  $wires[$n]->{rad} = $wires[$n]->{rad} * $scale;
  my($newDia)= $wires[$n]->{rad}*2;
  my($length) = $wires[$n]->{y2} - $wires[$n]->{y1};
  print "length is $length\n";
  $length = $length * 0.95;
  $wires[$n]->{y1} = $length/-2.0;
  $wires[$n]->{y2} = $length/2.0;
}

sub parseOutfile{
  my($name)=@_;
  my($result)={ fwd=>-999, rev=>-999};
  open(my $in,"<$necDir/out/$name") or die "failed to open results file $name: $!\n";
  my($trigger)=0;
  while(<$in>){
    chomp;
    my($line)=$_;
    if($line =~ /- - - ANTENNA INPUT PARAMETERS - - -/){
       while(<$in>){
         chomp;
         $line = $_;
         if($line =~ /^\s+\d+\s+\d+/){
           my(@d)= $line =~ /([+-]?\d+(?:\.\d+(?:E[+-]?\d+)?)?)/g;
           $result->{impedance}->{real}=eval($d[6]);
           $result->{impedance}->{imag}=eval($d[7]);
           $result->{swr}=calculateSwr($result->{impedance}->{real},$result->{impedance}->{imag});
           last;
         }
       }
    }
    if($line =~ /- - - RADIATION PATTERNS - - -/){
      $trigger=1;
    }
    if($line =~ /AVERAGE POWER GAIN/){
      $trigger=0;
    }
    if($line =~ /^\s\*\*/){
      $trigger=0;
    }
    if($trigger){
      if($line =~ /^\s+90\.00\s+0\.00/){
        my(@g)=split(/\s+/,$line);
        $result->{fwd}=$g[4];
      }
      if($line =~ /^\s+90\.00\s+180\.00/){
        my(@g)=split(/\s+/,$line);
        $result->{rev}=$g[4];
      }
    }
  }
  close $in;
  return $result;
}



sub runNec{
  my $cmd = "nec2dxs1k5.exe 0<..\\out\\optimiser.cmd > NUL 2>&1";
  open my $null_fh, '>', File::Spec->devnull or die "Can't open null file handle: $!";
  system("$cmd");
}

sub writeCommandFile{
   my($f1,$f2)=@_;
   open(my $out,">$necDir/out/optimiser.cmd") or die "failed write command file: $!\n";
   print $out "..\\out\\$f1\n";
   print $out "..\\out\\$f2\n";
   close $out;
}

sub writeOutfile{
   my($wires,$fr,$ex,$file,$scale)=@_;
   open(my $out,">$necDir/out/$file") or die "failed op open output file: $!\n";
   print $out "CM Optimiser intermediate file\n";
   print $out "CE\n";
   for my $i(1..$#{$wires}){
     my($wire)=$wires[$i];
     printf $out ("GW %d %d %0.4f %0.4f %0.4f %0.4f %0.4f %0.4f %0.4f\n", $wire->{tag},$wire->{segs},
     $wire->{x1}*$scale,$wire->{y1}*$scale,$wire->{z1}*$scale,
     $wire->{x2}*$scale,$wire->{y2}*$scale,$wire->{z2}*$scale,
     $wire->{rad}*$scale);
   }
   print $out "GE\n";
   print $out "GN\t-1\n";
   print $out "EK\n";
   print $out "EX 0 3 2 0 1 0 0\n";
   if($scale==1.0){
      print $out "FR 0 0 0 0 432.1 0\n";
      print $out "RP 0 1 3 1000 90 0 0 180\n";
   }else{
      print $out "FR 0 0 0 0 1296 0\n";
      print $out "RP 0 91 181 1003 -180 0 2 2\n";
   }
   
   close $out;
}

