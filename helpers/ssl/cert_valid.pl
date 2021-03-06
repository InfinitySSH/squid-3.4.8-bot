#!/usr/bin/perl -w
#
# A dummy SSL certificate validator helper that
# echos back all the SSL errors sent by Squid.
#

use warnings;
use strict;
use Getopt::Long;
use Pod::Usage;
use Crypt::OpenSSL::X509;
use FileHandle;
use POSIX qw(strftime);

my $debug = 0;
my $help = 0;

=pod

=head1 NAME

cert_valid.pl - A fake cert validation helper for Squid

=head1 SYNOPSIS

cert_valid.pl [-d | --debug] [-h | --help]

=over 8

=item  B<-h | --help>

brief help message

=item B<-d | --debug>

enable debug messages to stderr

=back

=head1 DESCRIPTION

Retrieves the SSL certificate error list from squid and echo back without any change.

=head1 COPYRIGHT

(C) 2012 The Measurement Factory, Author: Tsantilas Christos

This program is free software. You may redistribute copies of it under the
terms of the GNU General Public License version 2, or (at your opinion) any
later version.

=cut

GetOptions(
    'help' => \$help,
    'debug' => \$debug,
    ) or pod2usage(1);

pod2usage(1) if ($help);

$|=1;
while (<>) {
    my $first_line = $_;
    my @line_args = split;

    if ($first_line =~ /^\s*$/) {
        next;
    }

    my $response;
    my $haserror = 0;
    my $channelId = $line_args[0];
    my $code = $line_args[1];
    my $bodylen = $line_args[2];
    my $body = $line_args[3] . "\n";
    if ($channelId !~ /\d+/) {
        $response = $channelId." BH message=\"This helper is  concurrent and requires the concurrency option to be specified.\"\1";
    } elsif ($bodylen !~ /\d+/) {
        $response = $channelId." BH message=\"cert validator request syntax error \" \1";
    } else {
        my $readlen = length($body);
        my %certs = ();
        my %errors = ();
        my @responseErrors = ();

        while($readlen < $bodylen) {
	    my $t = <>;
            if (defined $t) {
                $body  = $body . $t;
                $readlen = length($body);
            }
        }

        print(STDERR logPrefix()."GOT ". "Code=".$code." $bodylen \n") if ($debug); #.$body;
        my $hostname;
        parseRequest($body, \$hostname, \%errors, \%certs);
        print(STDERR logPrefix()."Parse result: \n") if ($debug);
        print(STDERR logPrefix()."\tFOUND host:".$hostname."\n") if ($debug);
        print(STDERR logPrefix()."\tFOUND ERRORS:") if ($debug);
        foreach my $err (keys %errors) {
            print(STDERR logPrefix().$errors{$err}{"name"}."/".$errors{$err}{"cert"}." ,")  if ($debug);
        }
        print(STDERR "\n") if ($debug);
        foreach my $key (keys %certs) {
            ## Use "perldoc Crypt::OpenSSL::X509" for X509 available methods.
            print(STDERR logPrefix()."\tFOUND cert ".$key.": ".$certs{$key}->subject() . "\n") if ($debug);
        }

        #got the peer certificate ID. Assume that the peer certificate is the first one.
        my $peerCertId = (keys %certs)[0];

        # Echo back the errors: fill the responseErrors array  with the errors we read.
        foreach my $err (keys %errors) {
            $haserror = 1;
            appendError (\@responseErrors, 
                         $errors{$err}{"name"}, #The error name
                         "Checked by Cert Validator", # An error reason
                         $errors{$err}{"cert"} # The cert ID. We are always filling with the peer certificate.
                );
        }

        $response = createResponse(\@responseErrors);
        my $len = length($response);
        if ($haserror) {
            $response = $channelId." ERR ".$len." ".$response."\1";
        } else {
            $response = $channelId." OK ".$len." ".$response."\1";
        }
    }

    print $response;
    print(STDERR logPrefix().">> ".$response."\n") if ($debug);
}

sub trim
{
    my $s = shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub appendError
{
    my ($errorArrays) = shift;
    my($errorName) = shift;
    my($errorReason) = shift;
    my($errorCert) = shift;
    push @$errorArrays, { "error_name" => $errorName, "error_reason" => $errorReason, "error_cert" => $errorCert};
}

sub createResponse
{
    my ($responseErrors) = shift;
    my $response="";
    my $i = 0;
    foreach my $err (@$responseErrors) {
        $response=$response."error_name_".$i."=".$err->{"error_name"}."\n".
            "error_reason_".$i."=".$err->{"error_reason"}."\n".
            "error_cert_".$i."=".$err->{"error_cert"}."\n";
        $i++;
    }
    return $response;
}

sub parseRequest
{
    my($request)=shift;
    my $hostname = shift;
    my $errors = shift;
    my $certs = shift;
    while ($request !~ /^\s*$/) {
        $request = trim($request);
        if ($request =~ /^host=/) {
            my($vallen) = index($request, "\n");
            my $host = substr($request, 5, $vallen - 5);
            $$hostname = $host;
            $request =~ s/^host=.*$//m;
        }
        if ($request =~ /^cert_(\d+)=/) {
            my $certId = "cert_".$1;
            my($vallen) = index($request, "-----END CERTIFICATE-----") + length("-----END CERTIFICATE-----");
            my $x509 = Crypt::OpenSSL::X509->new_from_string(substr($request, index($request, "-----BEGIN")));
            $certs->{$certId} = $x509;
            $request = substr($request, $vallen);
        }
        elsif ($request =~ /^error_name_(\d+)=(.*)$/m) {
            my $errorId = $1;
            my $errorName = $2;
            $request =~ s/^error_name_\d+=.*$//m;
            $errors->{$errorId}{"name"} = $errorName;
        }
        elsif ($request =~ /^error_cert_(\d+)=(.*)$/m) {
            my $errorId = $1;
            my $certId = $2;
            $request =~ s/^error_cert_\d+=.*$//m;
            $errors->{$errorId}{"cert"} = $certId;
        }
        else {
            print(STDERR logPrefix()."ParseError on \"".$request."\"\n") if ($debug);
            $request = "";# finish processing....
        }
    }
}


sub logPrefix
{
  return strftime("%Y/%m/%d %H:%M:%S.0", localtime)." ".$0." ".$$." | " ;
}
