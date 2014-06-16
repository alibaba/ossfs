#!/usr/bin/env perl

use strict;
use warnings;

package OSS;

use LWP::UserAgent;
use HTTP::Date;
use MIME::Base64;
use Digest::MD5 qw(md5_base64);
use Digest::HMAC_SHA1;
use XML::Simple;

# for xml debug
# use Data::Dumper;
# print Dumper($xml);

sub new {
    my $class = shift;
    my $access_id = shift;
    my $access_key = shift;
    my $host = shift;

    $host = "oss.aliyuncs.com" unless (defined($host));
    my $ua = LWP::UserAgent->new(agent => "ossfs");
    my $self = {
        access_id => $access_id,
        access_key => $access_key,
        host => $host,
        ua => $ua
    };
    return bless $self, $class;
}

sub sign {
    my $self = shift;
    my $req = shift;
    my $canonicalized_resource = shift;

    my $verb = $req->method;
    my $md5 = "";
    if ($req->content) {
        $md5 = md5_base64($req->content) . "==";
        $req->header("Content-Md5" => $md5);
    }
    my $type = $req->header("Content-Type");
    $type = "" unless (defined($type));
    my $date = $req->header("Date");
    unless (defined($date)) {
        $date = time2str(time);
        $req->header("Date" => $date);
    }

    my $hmac = Digest::HMAC_SHA1->new($self->{access_key});
    $hmac->add("$verb\n$md5\n$type\n$date\n");

    my %canonicalized_oss_headers;
    foreach my $key ( $req->headers->header_field_names ) {
        if ($key =~ /^x-oss-/i) {
            $canonicalized_oss_headers{lc $key} = $req->header($key);
        }
    }
    foreach my $key ( sort map { lc } keys %canonicalized_oss_headers ) {
        $hmac->add("$key:$canonicalized_oss_headers{$key}\n");
    }
    $hmac->add($canonicalized_resource);

    $req->header("Authorization" => sprintf("OSS %s:%s",
                                            $self->{access_id},
                                            encode_base64($hmac->digest)));
    return $req;
}

# return 0|1 and a hash of { bucket_name => creation_date }
sub ListBucket {
    my $self = shift;

    my $req = $self->sign(
        HTTP::Request->new(GET => "http://$self->{host}/"), "/");
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        my %buckets;
        my $xml = XMLin($res->decoded_content, ForceArray => ['Bucket']);
        foreach ( @{ $xml->{Buckets}->{Bucket} } ) {
            $buckets{$_->{Name}} = str2time(
                $_->{CreationDate});
        }
        return (1, %buckets);
    }
    return 0;
}
sub GetService {
    return ListBucket(@_);
}

# return string "private", "public-read" or "public-read-write" or 0 on error
sub GetBucketACL {
    my $self = shift;
    my $bucket = shift;

    my $req = $self->sign(
        HTTP::Request->new(GET => "http://$bucket.$self->{host}/?acl"),
        "/$bucket/?acl");
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        my $xml = XMLin($res->decoded_content);
        return $xml->{AccessControlList}->{Grant};
    }
    return 0;
}

# return array of (0|1, files and dirs)
sub GetBucket {
    my $self = shift;
    my $bucket = shift;
    my %param = ( @_ );

    my @ret;
    my $param_str = "?";
    foreach my $key ( sort keys %param ) {
        $param_str .= "$key=$param{$key}&";
    }
    chop $param_str;
    my $req = $self->sign(
        HTTP::Request->new(GET => "http://$bucket.$self->{host}/$param_str"),
        "/$bucket/");
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        my $xml = XMLin($res->decoded_content,
                        ForceArray => ['Contents', 'CommonPrefixes']);
        # files
        foreach ( @{$xml->{Contents}} ) {
            my $f = $_->{Key};
            if (exists($param{"prefix"})) {
                $f = substr($f, length($param{"prefix"}));
            }
            push @ret, $f if ($f); # prefix itself should be removed
        }
        # dirs
        foreach ( @{$xml->{CommonPrefixes}} ) {
            my $d = $_->{Prefix};
            chop $d; # remove trailing "/"
            if (exists($param{"prefix"})) {
                $d = substr($d, length($param{"prefix"}));
            }
            push @ret, $d if ($d); # prefix itself should be removed
        }
        return (1, @ret);
    }
    return 0;
}

# return if success
sub PutBucket {
    my $self = shift;
    my $bucket = shift;

    my $req = $self->sign(
        HTTP::Request->new(PUT => "http://$bucket.$self->{host}/"),
        "/$bucket/");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# return if success
sub PutBucketACL {
    my $self = shift;
    my $bucket = shift;
    my $acl = shift;
    return 0 unless (grep {$_ eq $acl} ("public-read-write", "public-read", "private"));

    my $req = HTTP::Request->new(PUT => "http://$bucket.$self->{host}/");
    $req->header("x-oss-acl", $acl);
    $req = $self->sign($req, "/$bucket/");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# return if success
sub DeleteBucket {
    my $self = shift;
    my $bucket = shift;

    my $req = $self->sign(
        HTTP::Request->new(DELETE => "http://$bucket.$self->{host}/"),
        "/$bucket/");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# return if success
sub PutObject {
    my $self = shift;
    my $bucket = shift;
    my $object = shift;
    my $content = shift;
    my $type = shift;

    my $req = HTTP::Request->new(PUT => "http://$bucket.$self->{host}/$object");
    $req->header("Content-Type" => $type) if ($type);
    $req->header("Content-Length" => length($content));
    $req->content($content);
    $req = $self->sign($req, "/$bucket/$object");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# return if success
sub DeleteObject {
    my $self = shift;
    my $bucket = shift;
    my $object = shift;

    my $req = $self->sign(
        HTTP::Request->new(DELETE => "http://$bucket.$self->{host}/$object"),
        "/$bucket/$object");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# return array of (0|1, last-modified, content-size, content-type)
sub HeadObject {
    my $self = shift;
    my $bucket = shift;
    my $object = shift;

    my $req = $self->sign(
        HTTP::Request->new(HEAD => "http://$bucket.$self->{host}/$object"),
        "/$bucket/$object");
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        return (1,
                $res->header("Last-Modified"),
                $res->header("Content-Length"),
                $res->header("Content-Type"));
    }
    return 0;
}

# return string of content or undef on error
sub GetObject {
    my $self = shift;
    my $bucket = shift;
    my $object = shift;
    my $begin = shift;
    my $end = shift;

    my $req = $self->sign(
        HTTP::Request->new(GET => "http://$bucket.$self->{host}/$object"),
        "/$bucket/$object");
    if (defined($begin) and defined($end)) {
        $req->header(Range => "$begin-$end");
    }
    my $res = $self->{ua}->request($req);
    if ($res->is_success) {
        return $res->decoded_content;
    }
    return undef;
}

# return if success
sub CopyObject {
    my $self = shift;
    my $src_bucket = shift;
    my $src_object = shift;
    my $dest_bucket = shift;
    my $dest_object = shift;

    my $req = HTTP::Request->new(PUT => "http://$dest_bucket.$self->{host}/$dest_object");
    $req->header("x-oss-copy-source", "/$src_bucket/$src_object");
    $req = $self->sign($req, "/$dest_bucket/$dest_object");
    my $res = $self->{ua}->request($req);
    return $res->is_success;
}

# TODO: DeleteMultipleObjects
# TODO: MultipartUpload

1;
