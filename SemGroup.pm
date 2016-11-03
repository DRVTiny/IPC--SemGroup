use strict;
use 5.14.1;
use utf8;

use Carp qw(confess);
use Data::Dumper;

package IPC::SemGroup::Sem;
use IPC::SysV qw(ftok IPC_CREAT IPC_NOWAIT IPC_RMID GETVAL SETVAL);

sub new {
    my ($class,$name,$parent,$semnum)=@_;
    bless {
        'name'=>$name,
        'group'=>$parent,
        'num'=>$semnum,
        'groupid'=>$parent->get_id,
    }, (ref($class) || $class);
}

sub release {
    my $slf=shift;
    semop($slf->{'groupid'},pack('s*',$slf->{'num'},1,0));
}

sub take {
    my $slf=shift;
    semop($slf->{'groupid'},pack('s*',$slf->{'num'},-1,0));
}

sub take_nowait {
    my $slf=shift;
    semop($slf->{'groupid'},pack('s*',$slf->{'num'},-1,IPC_NOWAIT));
}

sub get {
    my $slf=shift;    
    semctl($slf->{'groupid'},$slf->{'semnum'},&GETVAL,0);
}

sub set {
    my ($slf,$newval)=@_;
    semctl($slf->{'groupid'},$slf->{'semnum'},&SETVAL,$newval);
}

sub DESTROY {
    my $slf=shift;
    say $slf->{'parent'}->('id');
}

package IPC::SemGroup;
use Carp qw(confess);
use IPC::SysV qw(ftok IPC_CREAT IPC_NOWAIT IPC_PRIVATE IPC_RMID);
use String::CRC32;
use Data::Dumper;

my $semPath=(grep {-e $_.'/IPC/SysV.pm'}  @INC)[0].'/IPC/SysV.pm';



sub new {
    my $class=shift;
# Here you will pass "semaphore names"
    confess 'Specify at least one semaphore name' unless my @piglets=@_; # nif-nif, nuf-nuf & naf-naf!
    
    my $c=0;
    $c++ until ref($piglets[$c]) or $c==@piglets;
    my %opts=ref($piglets[$c])?%{(splice @piglets,$c,scalar(@piglets),())[0]}:();    
    
    my $someNum=crc32(join ''=>@piglets);
    
    my %props=(
        'path'=>$semPath,
        'num'=>$someNum,
        'opts'=>\%opts,
    );
    
    confess 'Cant calculate key for the semaphore group object: '.$! 
        unless $props{'key'}=ftok($semPath,$someNum);
    confess 'Cant semget(). '.Dumper(\%props)
        unless $props{'id'}=semget($opts{'autodestroy'}?IPC_PRIVATE:$props{'key'},scalar(@piglets),IPC_CREAT | 0777);
        
    my $oSemGrp=bless sub {
        confess 'Internal datastructures unavailable outside the '.__PACKAGE__.' module' unless index((caller)[0], __PACKAGE__) == 0;
        return unless @_ and scalar(@_)<=2;
        return $props{$_[0]} if @_==1;
        $props{$_[0]}=$_[1];
    }, (ref $class || $class);
    
    do {
        my $c=0;
        $props{'sem'}{$_}=IPC::SemGroup::Sem->new($_,$oSemGrp,$c++) for @piglets;
    };
    
    return $oSemGrp;
}

sub _err {
    return unless ref(my $slf=shift) eq __PACKAGE__;
    return unless index((caller)[0], __PACKAGE__) eq 0;
    confess sprintf('semgroup[id=%s,key=%s]: ERROR: '.$_[0],$slf->_props(qw(id key)),@_[1..$#_])
}

sub _props {
    my $slf=shift;
    return unless index((caller)[0], __PACKAGE__) eq 0;
    return ( map $slf->($_), @_ );
}

sub _dump {
    return unless index((caller)[0], __PACKAGE__) eq 0;
    say Dumper(my $slf=shift);
    say 'Options: '.Dumper($slf->('opts')) if %{$slf->('opts')};
}

sub get_sem {
    return unless ref(my $slf=shift) eq __PACKAGE__;
    return unless @_;
    my $pigs=$slf->('sem');
    confess 'You must specify correct/initialized semaphore name for get_sem' unless defined(my $pig=$pigs->{$_[0]});
    return $pig;
}

sub get_id {
    return unless ref(my $slf=shift) eq __PACKAGE__;
    return $slf->('id');
}

sub DESTROY {
    my $slf=shift;
    if ( $slf->('opts')->{'autodestroy'} ) {
##DEBUG:       say STDERR 'Destroying semaphore group '.$slf->('id').'...';
        $slf->_err('Cant remove semaphore group on DESTROY') unless defined(my $res=semctl ( $slf->('id'), 0, &IPC_RMID, 0 ));
    }
}

1;
