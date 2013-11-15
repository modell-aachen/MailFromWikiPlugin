# See bottom of file for default license and copyright information

package Foswiki::Plugins::MailFromWikiPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Error ':try';
use HTML::Entities   ();

our $VERSION = '$Rev: 7808 (2010-06-15) $';
our $RELEASE = "1.0";

our $SHORTDESCRIPTION = 'Easily send mails from your wiki.';

our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ', # XXX method post, restauth
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerRESTHandler( 'sendmail', \&restSendmail );

    Foswiki::Func::addToZone( 'script', 'MailFromWikiPlugin', <<'SCRIPT', 'JQUERYPLUGIN::FOSWIKI' );
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/MailFromWikiPlugin/mailfromwiki.js' ></script>%JQREQUIRE{"ui::dialog, livequery, form,blockui"}%
SCRIPT

    # Plugin correctly initialized
    return 1;
}

sub restSendmail {
    my ( $session, $subject, $verb, $response ) = @_;

    # Format for sender
    my $from = $Foswiki::cfg{Plugins}{MailFromWikiPlugin}{FromTemplate} || '%WIKINAME% <%WIKIUSERMAIL%>';

    my $web = '';
    my $topic = '';
    try {
        throw Error::Simple( '%MAKETEXT{"You need to be logged in order to send mails"}%' ) if Foswiki::Func::isGuest();

        # find out which topic the mail was send from
        my $param = $session->{request}->{param};
        throw Error::Simple( '%MAKETEXT{"Missing parameters fromweb or fromtopic"}%' ) unless $param->{fromweb} && $param->{fromtopic};

        $web = $param->{fromweb}->[0];
        $topic = $param->{fromtopic}->[0];
        ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( $web, $topic );
        throw Error::Simple( '%MAKETEXT{"Topic [_1] does not exist." args="'."$web.$topic".'"}%' ) unless Foswiki::Func::topicExists( $web, $topic );

        # load template
        my $template = $param->{mailtemplate};
        $template = $template->[0] if $template;
        throw Error::Simple( '%MAKETEXT{"Missing email template."}%' ) unless $template;
        $template = "MailFromWiki${template}";
        Foswiki::Func::loadTemplate( $template, undef,  $web );
        my $mail = Foswiki::Func::loadTemplate( 'mailfromwiki' );

        # generate mail of sender and set as preference
        my @usermail = Foswiki::Func::wikinameToEmails();
        throw Error::Simple( '%MAKETEXT{"Could not determine you email."}%' ) unless scalar @usermail;
        Foswiki::Func::setPreferencesValue( 'WIKIUSERMAIL', $usermail[0] );

        # pretend this was rendered in fromweb.fromtopic and generate mail
        Foswiki::Func::setPreferencesValue( 'WEB', $web );
        Foswiki::Func::setPreferencesValue( 'TOPIC', $topic );
        Foswiki::Func::pushTopicContext( $web, $topic );
        try {
            # receipient
            my $to = Foswiki::Func::expandTemplate( 'To' );
            $to = Foswiki::Func::expandCommonVariables( $to );
            throw Error::Simple( '%MAKETEXT{"No recipient defined.' ) unless $to;
            my @emails;
            # Copy/Paste KVPPlugin
            foreach my $who ( @{_listToWikiNames( $to )} ) {
                if ( $who =~ /^$Foswiki::regex{emailAddrRegex}$/ ) {
                    push( @emails, $who );
                }
                else {
                    $who =~ s/^.*\.//;    # web name?
                    my @list = Foswiki::Func::wikinameToEmails($who);
                    if ( scalar(@list) ) {
                        push( @emails, @list );
                    }
                    else {
                        Foswiki::Func::writeWarning( __PACKAGE__
                              . " cannot send mail to '$who'"
                              . " - cannot determine an email address" );
                    }
                }

            }
            @emails = del_double(@emails);
            throw Error::Simple ( '%MAKETEXT{"Could not resolve mail adresses."}%' ) unless scalar @emails;
            Foswiki::Func::setPreferencesValue(
                'to_expanded',
                join( ', ', @emails )
            );

            # sender (continued)
            $from = Foswiki::Func::expandCommonVariables( $from );
            Foswiki::Func::setPreferencesValue( 'FROM', $from );

            # actual mail
            $mail = Foswiki::Func::expandCommonVariables( $mail );
            $mail = HTML::Entities::decode_entities( $mail );
            throw Error::Simple( '%MAKETEXT{"Could not load mail."}%' ) unless $mail;

            # send mails
            my $senderrors = Foswiki::Func::sendEmail( $mail, 5 );
            if ($senderrors) {
                Foswiki::Func::writeWarning(
                    'Failed to send ' + $template + ' mails: ' . $senderrors
                );
                throw Error::Simple( '%MAKETEXT{"Failed to send mails, please contact your administrator."}%' );
            }
        } finally {
            Foswiki::Func::popTopicContext();
        };
    } catch Error::Simple with { # report error
        my $error = shift->text();
        $error = Foswiki::Func::expandCommonVariables( $error );
        my $title = Foswiki::Func::expandCommonVariables( '%MAKETEXT{"Error sending mail."}%' );

        throw Foswiki::OopsException(
            'oopsgeneric',
            web    => $web,
            topic  => $topic,
            params => [ $title, $error || '?' ]
           );
    };

    # report success
    my $success = Foswiki::Func::expandTemplate( 'SuccessMessage' );
    $success = Foswiki::Func::expandCommonVariables( $success );
    return "<span class='message'>$success</span>";
}

# Copy/Paste KVPPlugin
# make entries unique
sub del_double{
        my %all=();
        @all{@_}=1;
        delete $all{''};
        return (keys %all);
}

# Copy/Paste KVPPlugin
# convert list of groups/users to list of WikiNames
sub _listToWikiNames {
    my ( $string ) = @_;
    $string =~ s#^\s*|\s*$##g;
    my @persons = ();
    # Alex: Get Users from Groups
    foreach my $group ( split(/\s*,\s*/, $string) ) {
        next unless $group;
        if ( Foswiki::Func::isGroup($group)) {
            my $it = Foswiki::Func::eachGroupMember($group);
            while ($it->hasNext()) {
                my $user = $it->next();
                push( @persons, $user);
            }
        }
        # Alex: Handler fr Nicht-Gruppen
        else {
            #Alex: Debug
            push( @persons, Foswiki::Func::getWikiName($group));
        }
    }
    return \@persons;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.