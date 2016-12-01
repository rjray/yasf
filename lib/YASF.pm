###############################################################################
#
# This file copyright © 2016 by Randy J. Ray, all rights reserved
#
# See "LICENSE AND COPYRIGHT" in the POD for terms.
#
###############################################################################
#
#   Description:    A string-formatter inspired by Python's format()
#
#   Functions:      YASF
#                   new
#                   bind
#                   format
#
#   Libraries:      None (only core)
#
#   Global Consts:  $TOKEN_RE
#
#   Environment:    None
#
###############################################################################

use 5.014;
use strict;
use warnings;

package YASF;

use overload fallback => 0,
    q{""} => \&_stringify,
    q{%}  => \&_interpolate;

use Carp qw(carp croak);
use English qw(-no_match_vars);
use Exporter qw(import);

BEGIN {
    no strict 'refs'; ## no critic (ProhibitNoStrict)

    for my $method (qw(template binding)) {
        *{$method} = sub { shift->{$method} }
    }
}

our @EXPORT_OK = qw(YASF);
my $TOKEN_RE = qr/(?^:((?:(?<!\\)[{](?:(?>[^{}]+)|(?-1))*(?<!\\)[}])))/x;

###############################################################################
#
#   Sub Name:       YASF
#
#   Description:    Shortcut to calling YASF->new($str) with no other args.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $template in      scalar    String template for formatter
#
#   Returns:        Success:    new object
#                   Failure:    dies
#
###############################################################################
## no critic(ProhibitSubroutinePrototypes)
sub YASF ($) { return YASF->new(shift); }

###############################################################################
#
#   Sub Name:       new
#
#   Description:    Class constructor. Creates the basic object and
#                   pre-compiles the template into the form that the formatter
#                   uses.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $class    in      scalar    Name of class
#                   $template in      scalar    String template for formatter
#                   @args     in      scalar    Everything else (see code)
#
#   Returns:        Success:    new object
#                   Failure:    dies
#
###############################################################################
sub new {
    my ($class, $template, @args) = @_;

    croak "${class}::new requires string template argument"
        if (! $template);

    my $args = @args == 1 ? $args[0] : { @args };
    my $self = bless { template => $template, binding => undef }, $class;

    $self->_compile;
    if ($args->{binding}) {
        $self->bind($args->{binding});
    }

    return $self;
}

###############################################################################
#
#   Sub Name:       bind
#
#   Description:    Add or change object-level bindings
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $bindings in      ref       New bindings
#
#   Returns:        Success:    $self
#                   Failure:    dies
#
###############################################################################
sub bind { ## no critic(ProhibitBuiltinHomonyms)
    my ($self, $bindings) = @_;

    state $not_acceptable = {
        SCALAR  => 1,
        CODE    => 1,
        REF     => 1,
        GLOB    => 1,
        LVALUE  => 1,
        FORMAT  => 1,
        IO      => 1,
        VSTRING => 1,
        Regexp  => 1,
    };

    if ((@_ == 2) && (! defined $bindings)) {
        # The means of unbinding is to call $obj->bind(undef):
        undef $self->{binding};
    } else {
        croak 'bind: New bindings must be provided as a parameter'
            if (! $bindings);

        my $type = ref $bindings;
        if ($not_acceptable->{$type}) {
            croak "New bindings reference type ($type) not usable";
        } elsif (! $type) {
            croak 'New bindings must be a reference (HASH, ARRAY or object)';
        }

        $self->{binding} = $bindings;
    }

    return $self;
}

###############################################################################
#
#   Sub Name:       _compile
#
#   Description:    Private sub that is a front-end to the recursive sub
#                   _compile_segment.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#
#   Returns:        Success:    void
#                   Failure:    dies
#
###############################################################################
sub _compile {
    my $self = shift;

    $self->{_compiled} = $self->_compile_segment($self->template);

    return;
}

###############################################################################
#
#   Sub Name:       _compile_segment
#
#   Description:    Private sub that compiles a segment of the template.
#                   Creates a listref of constant parts (strings) and nested
#                   expansion parts (listrefs).
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $segment  in      scalar    Text to be parsed into chunks
#                                                 for the formatter to use
#
#   Globals:        $TOKEN_RE
#
#   Returns:        Success:    array reference
#                   Failure:    dies
#
###############################################################################
sub _compile_segment {
    my ($self, $segment) = @_;
    my (@tokens, @compiled, $pos);

    while ($segment =~ /$TOKEN_RE/g) {
        push @tokens, [ $1, $LAST_MATCH_START[1], $LAST_MATCH_END[1] ];
    }

    $pos = 0;
    for my $token (@tokens) {
        my ($subsegment, $start, $end) = @{$token};
        if (my $len = $start - $pos) {
            push @compiled, substr $segment, $pos, $len;
        }
        push @compiled, $self->_compile_segment(substr $subsegment, 1, -1);
        $pos = $end;
    }

    if ($pos < length $segment) {
        push @compiled, substr $segment, $pos;
    }

    return \@compiled;
}

###############################################################################
#
#   Sub Name:       _stringify
#
#   Description:    Private sub that handles the stringification of the object
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#
#   Returns:        Success:    string
#                   Failure:    dies
#
###############################################################################
sub _stringify {
    my $self = shift;
    my $binding = $self->binding;

    return $binding ? $self->format($binding) : $self->template;
}

###############################################################################
#
#   Sub Name:       _interpolate
#
#   Description:    Private sub that handles the % interpolation of the object
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $bindings in      ref       The bindings passed to %
#                   $swap     in      scalar    A boolean that indicates if
#                                                 the object was before or
#                                                 after the operator
#
#   Returns:        Success:    string
#                   Failure:    dies
#
###############################################################################
sub _interpolate {
    my ($self, $bindings, $swap) = @_;

    if ($swap) {
        my $class = ref $self;
        croak "$class object must come first in % interpolation";
    }

    return $self->format($bindings);
}

###############################################################################
#
#   Sub Name:       format
#
#   Description:    Front-end to the recursive _format routine, which does the
#                   bulk of the parsing/interpolation of the object's template
#                   against the given bindings.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $bindings in      ref       Optional, bindings to use in
#                                                 interpolation. Defaults to
#                                                 object-level bindings.
#
#   Returns:        Success:    string
#                   Failure:    dies
#
###############################################################################
sub format { ## no critic(ProhibitBuiltinHomonyms)
    my ($self, $bindings) = @_;

    ## no critic(BuiltinFunctions::ProhibitUselessTopic)

    $bindings ||= $self->binding;
    croak 'format: Bindings are required if object has no internal binding'
        if (! $bindings);

    my $value = join q{} =>
        map { ref($_) ? $self->_format($bindings, @{$_}) : $_ }
        @{$self->{_compiled}};

    return $value;
}

###############################################################################
#
#   Sub Name:       _format
#
#   Description:    Private sub that does the hard and recursive part of the
#                   actual formatting. Only it isn't that hard, mostly just
#                   recursive.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $bindings in      ref       Bindings to format with
#
#   Returns:        Success:    string
#                   Failure:    dies
#
###############################################################################
sub _format {
    my ($self, $bindings, @elements) = @_;

    ## no critic(BuiltinFunctions::ProhibitUselessTopic)

    # Slight duplication of code from format() here, but it saves having to
    # keep track of depth and do a conditional on every return.
    my $expr = join q{} =>
        map { ref($_) ? $self->_format($bindings, @{$_}) : $_ } @elements;

    return $self->_expr_to_value($bindings, $expr);
}

###############################################################################
#
#   Sub Name:       _expr_to_value
#
#   Description:    Private sub that converts a key expression like "a.b.c"
#                   into a value from the bindings.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $bindings in      ref       Bindings to use for replacing
#                   $string   in      scalar    Expression to evaluate
#
#   Returns:        Success:    string
#                   Failure:    dies
#
###############################################################################
sub _expr_to_value {
    my ($self, $bindings, $string) = @_;

    my ($expr, $format) = split /:/ => $string, 2;
    # For now, $format is ignored
    my @hier = split /[.]/ => $expr;
    my $node = $bindings;

    for my $key (@hier) {
        if ($key =~ /^\d+$/) {
            if (ref $node eq 'ARRAY') {
                $node = $node->[$key];
            } else {
                croak "Key-type mismatch (key $key) in $expr, node is not " .
                    'an ARRAY ref';
            }
        } else {
            if (ref $node eq 'HASH') {
                $node = $node->{$key};
            } elsif (ref $node) {
                $node = $node->$key();
            } else {
                croak "Key-type mismatch (key $key) in $expr, node is not " .
                    'a HASH ref or object';
            }
        }
    }

    # Because all the key-substitution has been done before this sub is called,
    # it's probably a bad thing if $node is a ref. It's gonna get stringified
    # as a ref, which is probably not what the caller intended.
    if (ref $node) {
        carp "Format expression $expr yielded a reference value rather than " .
            'scalar';
    }
    return $node;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

YASF - Yet Another String Formatter

=head1 SYNOPSIS

    use YASF;
    use LWP::Simple;
    
    my $str = YASF->new('https://google.com/?q={search}');
    for my $term qw(<search terms>) {
        $results{$term} = get($str % { search => $term });
    }

=head1 DESCRIPTION

NOTE: This is an early release, and should be considered alpha-quality. The
interface is subject to change in future versions.

B<YASF> is a string-formatting module with functionality inspired by the C<%>
string operator and C<format> method of the string class from Python.

B<YASF> is not a direct port of these features, so they are not strictly
identical in nature. Instead, B<YASF> provides a handful of methods and an
overload of some operators. This allows you to create your template string and
interpolate it either with a direct call to B<format>, or using C<%> as an
operator similar in syntax to Python.

=head2 Interpolation Syntax

The syntax for interpolating the pattern string is fairly simple:

    "some text {key} some more text"

When interpolated, the string C<{key}> will be replaced with the value of C<key>
in the bindings for the interpolation.

Because the bindings can be almost any arbitrary Perl data structure, the keys
may be multi-part, in a hierarchy denoted by dots (C<.>):

    {key1.key2.key3}

The above will first look up C<key1> in the bindings, which it will expect to
be a hash reference. The value that C<key1> yields will also be expected to be
a hash reference, and C<key2> will be looked up in that table, and so on.

Keys may also be numeric, in which case it is expected that the corresponding
binding being indexed is an array reference:

    {3}

Numeric and string keys may be interspersed, if the underlying data structure
follows the same pattern:

    {key.0.name}

When a key expression is being evaluated into a value, an exception is thrown
if the key-type is not appropriate for the node at that position in the data
structure.

Keys may also be nested:

    {key.{subkey}}

In such a case, C<subkey> is evaluated first, and the value from it is used
to construct the full key.

The value from a nested key is not evaluated recursively, as this could lead to
endless recursion. That is, if C<subkey> evaluated to C<{key2}>, it would
B<not> result in C<key2> being interpolated. Instead, a literal key of
C<{key2}> would be looked up on the hash reference that C<key> yields.

=head2 Using Objects in the Bindings

If an element within the bindings data structure is an object, the key for
that node will be used as the name of a method and called on the object. The
method will be called with no parameters, and is expected to return a scalar
value (be that an ordinary value or a reference).

For example:

    require HTTP::Daemon;
    
    my $str = YASF->new("{d.product_tokens} listening at {d.url}\n");
    my $d = HTTP::Daemon->new;
    print $str % { d => $d };

However, in this case there's no reason that the object itself cannot be the
binding:

    require HTTP::Daemon;
    
    my $str = YASF->new("{product_tokens} listening at {url}\n");
    my $d = HTTP::Daemon->new;
    print $str % $d;

=head2 Formatting Syntax

Python's C<format> also supports an extensive syntax for formatting the data
that gets substituted.

This is not provided in this initial release of B<YASF>, but will be added
in a future release. For now, if a formatting string is detected it will be
ignored.

=head1 OVERLOADED OPERATORS

The B<YASF> class overrides a small number of operators. Any operators not
explicitly listed here will not fall back to any Perl defaults, they will
instead trigger a run-time error.

=over 4

=item C<%>

The C<%> operator causes the interpolation of a B<YASF> template against the
bindings that are passed following the operator:

    print $str % $data;
    # or
    print $str % { ... };
    # or
    print $str % [ ... ];

If the object has been bound to a data structure already (see the B<bind>
method, below), the explicitly-provided bindings take precedence over the
object-level binding.

=item C<""> (stringification)

When a B<YASF> object is stringified, one of two things happens:

=over

=item 1.

If the object is bound to a data structure via B<bind> (or from a C<binding>
argument in the constructor), it is interpolated against these bindings and
the resulting string is used.

=item 2.

If the object has not object-level binding, then the uninterpolated template
string will be used.

=back

You do not need to explicitly use double-quotes to trigger this; anywhere the
object would be used as a string (printing, hash keys, etc.), this will be the
behavior.

=back

=head1 SUBROUTINES/METHODS

The following methods and subroutines are provided by this module:

=over 4

=item B<new>

This is the object constructor. It takes one required argument and optional
named arguments following that. The required argument is the string template
that will be interpolated. The named arguments may be passed as a hash
reference or as key/value pairs. Currently, only one named parameter is
recognized:

=over

=item B<binding>

Specifies the bindings for the object. The value must be an array reference, a
hash reference, or an object referent.

=back

The return value is a new object of the class. Any errors will be signaled via
B<croak>.

=item B<bind>

This method binds the object to a data structure reference. When an object has
a bound data structure, it can be formatted or interpolated in a string without
needed explicit bindings to be provided. This can be useful when binding to a
hash reference whose contents will continually change, or an object whose
internal state is continuously changing.

The method takes one required argument, the new binding. This must be a
reference to a hash, to an array, or to an object. If the argument does not
meet these criteria (or is not given), an exception is thrown via B<croak>.

If an object has a bound data structure, but is interpolated with C<%> or
B<format> with an explicit binding, the explicit binding will supercede the
internal binding (but without replacing it permanently).

You can unbind data from the object by calling B<bind> with C<undef> as the
argument.

=item B<format>

This method formats the template within the object, using either bindings
provided as an argument or using the object-level bindings that are already
set.

=item B<binding>

A static accessor that returns the current object-level bindings data structure,
or B<undef> if there are no object-level bindings. Cannot be used to set the
bindings; see B<bind>, above.

=item B<template>

A static accessor that returns the template string that this object is
encapsulating. Cannot be used to change the template.

(At present, there is no way to change the template of an object. You can only
create a new object.)

=item B<YASF>

This is a convenience function for quickly creating an unbound B<YASF> object.
It requires the template string as the only parameter and returns a new object.
This can be useful for one-off usage, etc., and is a few characters shorter
than calling B<new> directly:

    require HTTP::Daemon;
    
    my $d = HTTP::Daemon->new;
    print YASF "{product_tokens} listening at {url}\n" % $d;

The only real difference between this and B<new>, is that you cannot pass any
additional arguments to B<YASF>.

The B<YASF> function is not exported by default; you must explicitly import it:

    use YASF 'YASF';

=back

=head1 DIAGNOSTICS

Presently, all errors are signaled via the B<croak> function. This may change
as the module evolves.

=head1 BUGS

As this is alpha software, the likelihood of bugs is pretty close to 100%.
Please report any issues you find to either the CPAN RT instance or to the
GitHub issues page:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=YASF>

=item * GitHub Issues page

L<https://github.com/rjray/yasf/issues>

=back

=head1 SUPPORT

=over 4

=item * Source code on GitHub

L<https://github.com/rjray/yasf>

=item * MetaCPAN

L<https://metacpan.org/release/YASF>

=back

=head1 LICENSE AND COPYRIGHT

This file and the code within are copyright © 2016 by Randy J. Ray.

Copying and distribution are permitted under the terms of the Artistic
License 1.0 or the GNU GPL 1. See the file F<LICENSE> in the distribution of
this module.

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>
