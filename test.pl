#!/usr/bin/env perl

push @INC, ".";

use strict;
use warnings;

use OSS;

my $case_id = 0;
sub case {
    my $name = shift;
    $case_id++;
    print "\n$case_id: $name\n\n";
}

my $fail = 0;
sub assert_eq {
    my $left = shift;
    my $right = shift;
    if ($left == $right) {
        print "OK, $right as expected.\n";
    } else {
        print "FAIL, $left expected but got $right\n";
        $fail++;
    }
}
sub assert_str_eq {
    my $left = shift;
    my $right = shift;
    if ($left eq $right) {
        print "OK, [$right] as expected.\n";
    } else {
        print "FAIL, [$left] expected but got [$right]\n";
        $fail++;
    }
}

my $oss = OSS->new("acpcwefkoxsh5cygh2uid01p",
                   "kDyCrM5S16udle+qaGf3mUAhxqQ=");

case("ListBucket");
my ($ret, %buckets) = $oss->ListBucket;
assert_eq(1, $ret);
foreach my $bucket ( keys %buckets ) {
    print "$bucket => $buckets{$bucket}\n";
}

case("GetBucketACL");
$oss->{bucket} = "lymanrb";
print $oss->GetBucketACL("lymanrb"), "\n";

case("GetBucket");
print join("\n", $oss->GetBucket("lymanrb")), "\n";

case("GetBucket w/ prefix and delimiter");
print join("\n", $oss->GetBucket("lymanrb", prefix => "foo/", delimiter => "/")), "\n";

case("PutObject");
assert_eq(1, $oss->PutObject("lymanrb", "test_tmp", "hello world!", "text/plain"));

case("PutObject empty file");
assert_eq(1, $oss->PutObject("lymanrb", "empty_tmp", ""));

case("HeadObject");
my ($ret, $ctime, $size, $type) = $oss->HeadObject("lymanrb", "test_tmp");
assert_eq(1, $ret);
print "$ctime\n$size\n";
print "$type\n" if (defined($type));

case("GetObject");
assert_str_eq("hello world!", $oss->GetObject("lymanrb", "test_tmp"));

case("CopyObject");
assert_eq(1, $oss->CopyObject("lymanrb", "test_tmp", "lymanrb", "tmp_test"));

case("HeadObject");
($ret, $ctime, $size, $type) = $oss->HeadObject("lymanrb", "tmp_test");
assert_eq(1, $ret);
print "$ctime\n$size\n";
print "$type\n" if (defined($type));

case("GetObject");
assert_str_eq("hello world!", $oss->GetObject("lymanrb", "tmp_test"));

case("DeleteObject");
assert_eq(1, $oss->DeleteObject("lymanrb", "test_tmp"));
assert_eq(1, $oss->DeleteObject("lymanrb", "tmp_test"));
assert_eq(1, $oss->DeleteObject("lymanrb", "empty_tmp"));

print "\n$fail failed.\n";
exit ($fail == 0) ? 0 : 1;
