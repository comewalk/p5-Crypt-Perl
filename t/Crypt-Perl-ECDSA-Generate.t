package t::Crypt::Perl::ECDSA::Generate;

use strict;
use warnings;

BEGIN {
    if ( $^V ge v5.10.1 ) {
        require autodie;
    }
}

use Try::Tiny;

use FindBin;

use lib "$FindBin::Bin/lib";
use OpenSSL_Control ();

use Test::More;
use Test::NoWarnings;
use Test::Deep;
use Test::Exception;

use Crypt::Format ();
use Digest::SHA ();
use File::Slurp ();
use File::Temp ();
use IPC::Open3 ();
use Symbol::Get ();

use Crypt::Perl::ECDSA::EC::DB ();

use lib "$FindBin::Bin/lib";
use parent qw(
    NeedsOpenSSL
    Test::Class
);

use OpenSSL_Control ();

use lib "$FindBin::Bin/../lib";

use Crypt::Perl::ECDSA::Generate ();

if ( !caller ) {
    my $test_obj = __PACKAGE__->new();
    plan tests => $test_obj->expected_tests(+1);
    $test_obj->runtests();
}

#----------------------------------------------------------------------

sub new {
    my ($class) = @_;

    my $self = $class->SUPER::new();

    $self->num_method_tests(
        'test_generate',
        (4 * @{ [ $self->_KEY_TYPES_TO_TEST() ] }),
    );

    return $self;
}

#Should this logic Go into EC::DB, to harvest all working
#curve names?
sub _KEY_TYPES_TO_TEST {
    my @names = Symbol::Get::get_names('Crypt::Perl::ECDSA::EC::CurvesDB');

    my @curves;
    for my $name (sort @names) {
        next if $name !~ m<\AOID_(.+)>;

        my $curve = $1;

        try {
            Crypt::Perl::ECDSA::EC::DB::get_curve_data_by_name($curve);
            push @curves, $curve;
        }
        catch {
            diag( sprintf "Skipping “$curve” (%s) …", ref $_ );
        };
    }

    return @curves;
}

sub test_generate : Tests(9) {
    my ($self) = @_;

    my $msg = rand;

    #Use SHA1 since it’s the smallest digest that the latest OpenSSL accepts.
    my $dgst = Digest::SHA::sha1($msg);
    my $digest_alg = 'sha1';

    for my $curve ( $self->_KEY_TYPES_TO_TEST() ) {
        my $key_obj = Crypt::Perl::ECDSA::Generate::by_name($curve);

        isa_ok(
            $key_obj,
            'Crypt::Perl::ECDSA::PrivateKey',
            "$curve: return of by_name()",
        );

        IPC::Open3::open3( my $wfh, my $rfh, undef, "$self->{'_ossl_bin'} ec -text" );
        print {$wfh} $key_obj->to_pem_with_curve_name() or die $!;
        close $wfh;
        my $parsed = do { local $/; <$rfh> };
        close $rfh;

        ok( !$?, "$curve: OpenSSL parses OK" ) or diag $parsed;

      SKIP: {
            try {
                my $sig = $key_obj->sign($dgst);

                ok( $key_obj->verify( $dgst, $sig ), 'verify() on self' );

                ok(
                    OpenSSL_Control::verify_private(
                        Crypt::Format::der2pem($key_obj->to_der_with_curve_name(), 'EC PRIVATE KEY'),
                        $msg,
                        $digest_alg,
                        $sig,
                    ),
                    "$curve: OpenSSL verifies",
                ) or print $key_obj->to_pem_with_curve_name() . "\n";
            }
            catch {
                if ( try { $_->isa('Crypt::Perl::X::TooLongToSign') } ) {
                    skip $_->to_string(), 2;
                }
                else {
                    local $@ = $_; die;
                }
            };
        }
    }

    return;
}

1;
