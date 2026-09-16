#!/usr/bin/env perl
# Uncontended owner-link primitives for short native Windows hook transactions.
# Called only by fm-wake-lib.sh with that Bash frame's PID and absolute lock path.
# Uses the SAME populated-owner-directory/symlink protocol as the Bash owner;
# stale recovery, waiting, roles, and lifecycle authority remain in that owner.
# Never reclaims a lock or follows an unexpected owner path. All checks are fresh.
# Exit 0: acquired (stdout owner path) or safely released/not-owned; nonzero:
# caller uses the existing guarded Bash path. MSYS=winsymlinks:sys is required
# on Git for Windows, exactly as for the Bash owner's ln invocation.
use strict;
use warnings;
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);

my ($operation, $lock, $pid) = @ARGV;
exit 2 unless @ARGV == 3 && $operation =~ /\A(?:acquire|release)\z/
    && $pid =~ /\A[1-9][0-9]*\z/ && $lock =~ m{\A/} && $lock !~ /[\x00-\x1f\x7f]/;
umask 0077;
sub read_record {
    my ($file) = @_;
    open my $fh, '<', $file or return;
    local $/;
    my $value = <$fh>;
    close $fh;
    return unless defined $value && $value !~ /\x00/;
    $value =~ s/\n+\z//;
    return $value;
}
sub points_to {
    my ($path, $owner) = @_;
    my $actual = readlink $path;
    return defined($actual) && $actual eq $owner;
}
sub discard_owner {
    my ($owner) = @_;
    return unless -d $owner && !-l $owner && index($owner, "$lock.owner.") == 0;
    unlink map { "$owner/$_" } qw(pid fm-home pid-identity role watcher-path);
    rmdir $owner;
}
if ($operation eq 'release') {
    # A legacy directory lock stays on the ordinary Bash release path.
    exit 1 unless -l $lock;
    my $owner = readlink $lock;
    exit 1 unless defined($owner) && index($owner, "$lock.owner.") == 0 && -d $owner && !-l $owner;
    my $owner_pid = read_record("$owner/pid");
    exit 0 unless defined($owner_pid) && $owner_pid eq $pid;
    exit 0 unless points_to($lock, $owner);
    exit 1 unless unlink $lock;
    discard_owner($owner);
    exit 0;
}
exit 1 if -e $lock || -l $lock;
# Use the same mktemp primitive as the Bash owner. Loading File::Temp and its
# dependency tree costs more on native Windows than this single bounded tool.
open my $maker, '-|', 'mktemp', '-d', "$lock.owner.XXXXXX" or exit 1;
my $owner = do { local $/; <$maker> };
close $maker or exit 1;
exit 1 unless defined $owner;
$owner =~ s/\n+\z//;
exit 1 unless index($owner, "$lock.owner.") == 0 && $owner !~ /[\x00-\x1f\x7f]/ && -d $owner && !-l $owner;
my $published = 0;
my $ok = eval {
    die "occupied" if -e $lock || -l $lock;
    sysopen my $fh, "$owner/pid", O_WRONLY | O_CREAT | O_EXCL, 0600 or die "pid";
    print {$fh} "$pid\n" or die "write";
    close $fh or die "close";
    my $back = read_record("$owner/pid");
    die "owner" unless defined($back) && $back eq $pid;
    symlink $owner, $lock or die "publish";
    $published = 1;
    die "identity" unless points_to($lock, $owner);
    # Preserve the ordinary claim's post-publication PID/readback and steal
    # checks; no cached identity can authorize removing a contender's link.
    open my $claim, '>', "$owner/pid" or die "claim";
    print {$claim} "$pid\n" or die "claim write";
    close $claim or die "claim close";
    $back = read_record("$owner/pid");
    die "claim identity" unless defined($back) && $back eq $pid && points_to($lock, $owner);
    die "steal" if -e "$lock.steal" || -l "$lock.steal";
    1;
};
unless ($ok) {
    unlink $lock if $published && points_to($lock, $owner);
    discard_owner($owner);
    exit 1;
}
print "$owner\n";
exit 0;
