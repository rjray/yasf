#!/usr/bin/perl

# Basic tests on object properties (accessors, etc.)

use 5.008;
use strict;
use warnings;

use File::stat ();

use Test::More;

use YASF;

plan tests => 20;

# I use Perl::Critic on tests. These two policies are not important in this
# suite:
## no critic(ValuesAndExpressions::RequireInterpolationOfMetachars)
## no critic(RegularExpressions::RequireExtendedFormatting)

my ($str, $result, $bind, $warning);
local $SIG{__WARN__} = sub {
    $warning = shift;
    return;
};

# Try the constructor with no args (should fail)
$result = eval { $str = YASF->new; };
like($@, qr/new requires string template/i, 'Empty constructor fails');

# Proper constructor call
$str = YASF->new('{foo}');
isa_ok($str, 'YASF', '$str');
is($str->template, '{foo}', 'template() method');
ok(! defined $str->binding, 'binding() method returns undef');

# Proper constructor (2)
$bind = {};
$str = YASF->new('{bar}', binding => $bind);
isa_ok($str, 'YASF', '$str');
is($str->binding, $bind, 'binding() method (non-undef)');

# Error cases for the bind() method
$result = eval { $str->bind; };
like($@, qr/new bindings must be provided/i, 'Empty call to bind() fails');
$result = eval { $str->bind('must be a reference'); };
like($@, qr/new bindings must be a reference/i, 'Call to bind() with non-ref');
$result = eval { $str->bind(\my $foo); };
like($@, qr/reference type .* not usable/i, 'Call to bind with unusable ref');

# Correct bind() calls
$str->bind($bind);
is($str->binding, $bind, 'bind() method (hashref)');
$bind = [];
$str->bind($bind);
is($str->binding, $bind, 'bind() method (listref)');
$bind = File::stat::stat($0);
$str->bind($bind);
is($str->binding, $bind, 'bind() method (object)');
$str->bind(undef);
ok(! defined $str->binding, 'bind(undef) clears');

# Errors/warnings from format()
$result = eval { $str->format; };
like($@, qr/bindings are required if object has no internal binding/i,
     'format() with no arg and no bindings');
$result = $str->format({ bar => [] });
like($warning, qr/format expression bar yielded a reference/i,
     'format() warning for references');
$str = YASF->new('{node.a}');
$result = eval { $str->format({ node => [] }); };
like($@, qr/key-type mismatch .* node is an array ref/i,
     'format() key mismatch (1)');
$result = eval { $str->format({ node => 1 }); };
like($@, qr/key-type mismatch .* node is not a hash ref/i,
     'format() key mismatch (2)');
$str = YASF->new('{node.0}');
$result = eval { $str->format({ node => {} }); };
like($@, qr/key-type mismatch .* node is not an array ref/i,
     'format() key mismatch (3)');

# Errors in operators
$result = eval { $bind % $str; };
like($@, qr/object must come first in % interpolation/i, '% param order');

# Expected operator behavior
is($str cmp '{node.0}', 0, 'cmp operator');

exit;
