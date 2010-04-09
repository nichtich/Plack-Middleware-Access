package Plack::Middleware::Access;

use strict;
use warnings;

use parent qw(Plack::Middleware);

use Plack::Util::Accessor qw(rules deny_page);

use Carp qw(croak);
use Net::IP;

our $VERSION = 0.0.1;

sub prepare_app {
    my $self = shift;

    if (!defined($self->deny_page)) {
        $self->deny_page(\&_deny_page);
    } elsif (ref($self->deny_page) ne 'CODE') {
        croak "deny_page should be a CODEREF";
    }

    if (defined($self->rules) && ref($self->rules) ne 'ARRAY') {
        croak "rules should be an ARRAYREF";
    }

    my @rules = $self->rules ? @{$self->rules} : ();
    my @typed_rules = ();

    if (@rules % 2 != 0) {
        croak "rules should contains even number of params";
    }

    foreach (my $i = 0; $i < @rules; $i += 2) {
        my $allowing = $rules[$i];
        my $rule_arg = $rules[$i + 1];
        if ($allowing !~ /^(allow|deny)$/) {
            croak "first argument of each rule should be 'allow' or 'deny'";
        }
        if (!defined($rule_arg)) {
            croak "rule argument should not be undefined";
        }
        $allowing = ($allowing eq 'allow') ? 1 : 0;
        if (ref($rule_arg) eq 'CODE') {
            push @typed_rules, [$allowing, "sub", $rule_arg];
        } elsif ($rule_arg eq 'all') {
            push @typed_rules, [$allowing, 'all'];
        } elsif ($rule_arg =~ /[A-Z]$/i) {
            push @typed_rules, [ $allowing, "host", qr/^(.*\.)?\Q${rule_arg}\E$/ ];
        } else {
            my $ip = Net::IP->new($rule_arg) or die "not supported type of rule argument [$rule_arg] or bad ip: " . Net::IP::Error();
            push @typed_rules, [ $allowing, "ip", $ip ];
        }
    }
    $self->rules(\@typed_rules);
}

sub call {
    my ($self, $env) = @_;

    my $rule_allowing;
    foreach my $rule (@{ $self->rules }) {
        my ($allowing, $rule_type, $rule_arg) = @{$rule};
        if ($rule_type eq 'sub') {
            $rule_allowing = $allowing if ($rule_arg->($env));
        } if ($rule_type eq 'all') {
            $rule_allowing = $allowing;
            last;
        } elsif ($rule_type eq 'host') {
            my $host = $env->{REMOTE_HOST};
            if (defined($host) && $host =~ $rule_arg) {
                $rule_allowing = $allowing;
                last;
            }
        } elsif ($rule_type eq 'ip') {
            my $addr = $env->{REMOTE_ADDR};
            my $ip;
            if (defined($addr) && ($ip = Net::IP->new($addr))) {
                my $overlaps = $rule_arg->overlaps($ip);
                if ($overlaps == $IP_B_IN_A_OVERLAP ||
                    $overlaps == $IP_IDENTICAL)
                {
                    $rule_allowing = $allowing;
                    last;
                }
            }
        }
    }

    if (!defined($rule_allowing) || $rule_allowing == 1) {
        return $self->app->($env);
    } else {
        if ($self->deny_page) {
            return $self->deny_page->($env);
        } else {

        }
    }
}

sub _deny_page {
    return [403,
            ['Content-Type' => 'text/plain'],
            ["You are not allowed to view this page."]];
}

1;

=head1 NAME

Plack::Middleware::Access - don't allow to open your app depending on the remote ip and other parameters

=head1 SYNOPSIS

  # in your app.psgi
  use Plack::Builder;

  builder {
    enable "Access" rules => [ allow => "goodhost.com",
                               allow => sub { <some code that returns true or false> },
                               allow => "192.168.1.5",
                               deny  => "192.168.1.0/24",
                               allow => "192.0.0.10",
                               deny  => "all" ];
    $app;
  };

=head1 DESCRIPTION

This middleware intended for restricting access to your app by some users.
It is very similar with allow/deny directives in web-servers.

=head1 CONFIGURATION

=over 4

=item rules

C<rules> is an ARRAYREF of rules. Each rule consists of directive C<allow> or
C<deny> and their argument.
Rules are checked in the order of their record to the first match.
If no rule matched then user have access to app.

Argument for the rule is a one of four possibilites:

=over 4

=item "all"

Always matched. Typical use-case is a deny => "all" in the end of rules.

=item remote_host

Matches on domain or subdomain of remote_host if it can be resolved.

=item ip

Matches on one ip or ip range. See L<Net::IP> for detailed description of
possible variants.

=item code

You can pass an arbitrary coderef for checking some specific params of request
such as user browser and so on. This function takes C<$env> as parameter.

=back

=item deny_page

It is a CODEREF to function that accepts an C<$env> and returns PSGI-compliant response.
By default middleware returns page with 403 status.

=back

=head1 AUTHORS

Yury Zavarin C<yury.zavarin@gmail.com>.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<http://github.com/tadam/Plack-Middleware-Access>
L<Net::IP>

=cut
