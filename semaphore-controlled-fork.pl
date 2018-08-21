#!/usr/bin/perl

use warnings;
use strict;

use IPC::SysV qw(S_IRUSR S_IWUSR IPC_CREAT IPC_NOWAIT);
use IPC::Semaphore;
use Time::HiRes ('sleep');

my $maxProcesses = 10;
my $startDepth   = 5;

# we use only one semaphore with the program name as key
my $semKey       = "$0";

my $INC          = 1;
my $DEC          = -1;

# recursive forking using a semaphore to limit the total number of processes

my $sem;

# clear the semaphore on stop
$SIG{INT} = sub {
    $sem->remove;
    exit 1;
};

sub process {
    my $level = shift;

    # end recursion with level <=0
    return if $level <= 0;

    # wait for dying child processes
    $SIG{CHLD} = sub {
        my $pid = wait();
        print "exit $pid\n";
    };

    my $val = $sem->getval(0);
    print "pid=$$, level=$level, used=" . ( $maxProcesses - $val ) . "\n";

    # simulate we are doing something
    sleep( rand() );

    # fork one process less than one level up
    for ( 1 .. $level - 1 ) {

        # check if the semaphore value can be decreased
        if ( $sem->op( 0, $DEC, IPC_NOWAIT ) ) {

            # fork process
            my $pid = fork();
            die "fork() failed: $!" unless defined $pid;
            if ($pid) {

                # parent:
                print "fork $pid\n";
            }
            else {
                # child process : recursive call with lower level
                eval { process( $level - 1 ); };

                # increase semaphore value after process is finished
                $sem->op( 0, $INC, 0 );
                exit;
            }

        } else {
            print "all processes are busy\n";
            process( $level - 1 );
        }
    }
}

sub main {

    # remove any other semaphore using the same key
    $sem =
      IPC::Semaphore->new( $semKey, 1, S_IRUSR | S_IWUSR | IPC_CREAT );
    $sem->remove;

    $sem =
      IPC::Semaphore->new( $semKey, 1, S_IRUSR | S_IWUSR | IPC_CREAT );

    # set initial semaphore value
    print "set max=$maxProcesses\n";
    $sem->setval( 0, $maxProcesses ) || die "can't set sems $!";

    # start processes
    process($startDepth);
    return if $maxProcesses == 0;

    my $c     = 0;
    while (1) {
        print "iteration $c\n";
        # finish if all processes are free again
        my $val = $sem->getval(0);
        last if $val == $maxProcesses;
        sleep 0.1;
        $c++;
    }
}

main();
$sem->remove;
