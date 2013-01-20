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

my $bucket = "lyman-ossfs-unittest";

case("PutBucket"); {
    # clear first
    $oss->DeleteBucket($bucket);
    assert_eq(1, $oss->PutBucket($bucket));
}

case("ListBucket");
{
    my ($ret, %buckets) = $oss->ListBucket;
    assert_eq(1, $ret);
    foreach my $bucket ( keys %buckets ) {
        print "$bucket => $buckets{$bucket}\n";
    }
    assert_eq(1, exists($buckets{$bucket}));
}

case("GetBucketACL");
{
    assert_str_eq("private", $oss->GetBucketACL($bucket));
}

case("PutBucketACL as modifier");
{
    assert_eq(1, $oss->PutBucketACL($bucket, "public-read"));
    assert_str_eq("public-read", $oss->GetBucketACL($bucket));
}

case("PutObject");
{
    assert_eq(1, $oss->PutObject($bucket, "foo",
                                 "hello world!", "text/plain"));
}

case("GetObject");
{
    assert_str_eq("hello world!", $oss->GetObject($bucket, "foo"));
}

case("PutObject empty file");
{
    assert_eq(1, $oss->PutObject($bucket, "empty", ""));
}

case("HeadObject");
{
    print "foo\n";
    my ($ret, $ctime, $size, $type) = $oss->HeadObject($bucket, "foo");
    assert_eq(1, $ret);
    assert_eq(12, $size);
    assert_str_eq("text/plain", $type);

    print "empty\n";
    ($ret, $ctime, $size, $type) = $oss->HeadObject($bucket, "empty");
    assert_eq(1, $ret);
    assert_eq(0, $size);
    print "$ctime\n";
    print "$type\n" if (defined($type));
}

case("CopyObject");
{
    assert_eq(1, $oss->CopyObject($bucket, "foo", $bucket, "bar/copy"));

    assert_str_eq("hello world!", $oss->GetObject($bucket, "bar/copy"));

    my ($ret, $ctime, $size, $type) = $oss->HeadObject($bucket, "bar/copy");
    assert_eq(1, $ret);
    assert_eq(12, $size);
    assert_str_eq("text/plain", $type);
}

case("GetBucket");
{
    my ($ret, @files) = $oss->GetBucket($bucket);
    assert_eq(1, $ret);
    assert_str_eq("foo", grep {$_ eq "foo"} @files);
    assert_str_eq("bar/copy", grep {$_ eq "bar/copy"} @files);
    assert_str_eq("empty", grep {$_ eq "empty"} @files);
}

case("GetBucket w/ prefix and delimiter");
{
    my ($ret, @files) = $oss->GetBucket($bucket,
                                        prefix => "bar/",
                                        delimiter => "/");
    assert_eq(1, $ret);
    assert_eq(0, $#files);
    assert_str_eq("copy", $files[0]);
}

case("DeleteObject");
{
    assert_eq(1, $oss->DeleteObject($bucket, "foo"));

    my ($ret, @files) = $oss->GetBucket($bucket);
    assert_eq(0, scalar grep {$_ eq "foo"} @files);
    assert_eq(1, $#files);
    assert_eq(1, $oss->DeleteObject($bucket, "empty"));
    assert_eq(1, $oss->DeleteObject($bucket, "bar/copy"));
}

case("DeleteBucket");
{
    assert_eq(1, $oss->DeleteBucket($bucket));
    my ($ret, %buckets) = $oss->ListBucket;
    assert_eq(1, $ret);
    assert_eq(0, scalar grep {$_ eq $bucket} keys %buckets);
}

case("PutBucketACL as creator");
{
    my $acl = "public-read";
    # create
    $oss->DeleteBucket($bucket);
    assert_eq(1, $oss->PutBucketACL($bucket, $acl));
    # assert existence
    my (undef, %buckets) = $oss->ListBucket;
    assert_eq(1, exists($buckets{$bucket}));
    # assert acl
    assert_str_eq($acl, $oss->GetBucketACL($bucket));
    # delete
    assert_eq(1, $oss->DeleteBucket($bucket));
}

if ($fail == 0) {
    print "\ndone.\n";
    exit 0;
} else {
    print "\n$fail failed.\n";
    exit 1;
}
