#!/usr/bin/perl
# --
# bin/znuny.SessionCreate.pl - prints an URL to the OTRS with a valid SessionID for the wanted User or CustomerUser
# Copyright (C) 2014 Znuny GmbH, http://znuny.com/
# --

use strict;
use warnings;

use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Kernel/cpan-lib';
use lib dirname($RealBin) . '/Custom';

use Getopt::Long;

use Kernel::Config;
use Kernel::System::Time;
use Kernel::System::Log;
use Kernel::System::Main;
use Kernel::System::Encode;
use Kernel::System::DB;
use Kernel::System::User;
use Kernel::System::CustomerUser;
use Kernel::System::Group;
use Kernel::System::CustomerGroup;
use Kernel::System::AuthSession;

# get options
my %Opts;
GetOptions(
    'userlogin|u=s' => \$Opts{UserLogin},
    'usertype|t=s'  => \$Opts{UserType},
    'help|h'        => \$Opts{Help},
);

# common objects
my %CommonObject;
$CommonObject{ConfigObject} = Kernel::Config->new();
$CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
$CommonObject{LogObject}    = Kernel::System::Log->new(
    LogPrefix => 'OTRS-znuny.SessionCreate.pl',
    %CommonObject,
);
$CommonObject{TimeObject}          = Kernel::System::Time->new(%CommonObject);
$CommonObject{MainObject}          = Kernel::System::Main->new(%CommonObject);
$CommonObject{EncodeObject}        = Kernel::System::Encode->new(%CommonObject);
$CommonObject{DBObject}            = Kernel::System::DB->new(%CommonObject);
$CommonObject{UserObject}          = Kernel::System::User->new(%CommonObject);
$CommonObject{CustomerUserObject}  = Kernel::System::CustomerUser->new(%CommonObject);
$CommonObject{GroupObject}         = Kernel::System::Group->new(%CommonObject);
$CommonObject{CustomerGroupObject} = Kernel::System::CustomerGroup->new(%CommonObject);
$CommonObject{SessionObject}       = Kernel::System::AuthSession->new(%CommonObject);

if (
    $Opts{Help}
    || !$Opts{UserLogin}
) {
    print STDOUT "znuny.SessionCreate.pl - prints an URL to the OTRS with a valid SessionID for the wanted User or CustomerUser\n";
    print STDOUT "Copyright (C) 2014 Znuny GmbH, http://znuny.com/\n";
    print STDOUT "usage: znuny.SessionCreate.pl

Required parameters:
    -[-u]serlogin  - the login of the user for which the session should be created

Optional parameters:
    --user[t]ype - define the session type 'User' (default) or 'Customer'
    -[-h]elp     - print this help text\n";
    exit 0;
}

# set default if no value given
$Opts{UserType} ||= 'User';

if ( lc $Opts{UserType} eq lc 'User' ) {
    $Opts{UserType} = 'User';
}
elsif ( lc $Opts{UserType} eq lc 'Customer' ) {
    $Opts{UserType} = 'Customer';
}
else {
    $CommonObject{LogObject}->Log(
        Priority => 'error',
        Message  => "Invalid user type '$Opts{UserType}'. Only 'User' and 'Customer' are valid.",
    );
    exit 1;
}

if ( $CommonObject{ConfigObject}->Get('SessionCheckRemoteIP') ) {

    $CommonObject{LogObject}->Log(
        Priority => 'error',
        Message  => "SysConfig 'SessionCheckRemoteIP' is enabled - this will lock SessionIDs out generated with this script.",
    );
    exit 1;
}

# get UserData for User/CustomerUser
my $UserObject         = 'UserObject';
my $UserObjectFunction = 'GetUserData';

if ( $Opts{UserType} eq 'Customer' ) {
    $UserObject         = 'CustomerUserObject';
    $UserObjectFunction = 'CustomerUserDataGet';
}

my %UserData = $CommonObject{ $UserObject }->$UserObjectFunction(
    User  => $Opts{UserLogin},
    Valid => 1,
);

if ( !%UserData ) {

    $CommonObject{LogObject}->Log(
        Priority => 'error',
        Message  => "Error while getting user data for $Opts{UserType} '$Opts{UserLogin}'.",
    );
    exit 1;
}

# get groups rw/ro
for my $Type (qw(rw ro)) {

    my $GroupObject = 'GroupObject';
    if ( $Opts{UserType} eq 'Customer' ) {
        $GroupObject = 'CustomerGroupObject';
    }

    my %GroupData = $CommonObject{ $GroupObject }->GroupMemberList(
        Result => 'HASH',
        Type   => $Type,
        UserID => $UserData{UserID},
    );
    for ( sort keys %GroupData ) {
        if ( $Type eq 'rw' ) {
            $UserData{"UserIsGroup[$GroupData{$_}]"} = 'Yes';
        }
        else {
            $UserData{"UserIsGroupRo[$GroupData{$_}]"} = 'Yes';
        }
    }
}

# create new session id
my $NewSessionID = $CommonObject{SessionObject}->CreateSessionID(
    %UserData,
    UserLastRequest => $CommonObject{TimeObject}->SystemTime(),
    UserType        => $Opts{UserType},
);

if ( !$NewSessionID ) {

    $CommonObject{LogObject}->Log(
        Priority => 'error',
        Message  => "Error while generating SessionID for $Opts{UserType} '$Opts{UserLogin}'.",
    );
    exit 1;
}

my %URLConfigs = (
    HttpType                 => '',
    FQDN                     => '',
    ScriptAlias              => '',
    SessionName              => '',
    CustomerPanelSessionName => '',
);

for my $ConfigName ( keys %URLConfigs ) {
    $URLConfigs{ $ConfigName } = $CommonObject{ConfigObject}->Get( $ConfigName );
}

$URLConfigs{SessionID} = $NewSessionID;

my $URLStub = '<OTRS_CONFIG_HttpType>://<OTRS_CONFIG_FQDN>/<OTRS_CONFIG_ScriptAlias>';
if ( $Opts{UserType} eq 'User' ) {
    $URLStub .= 'index.pl?<OTRS_CONFIG_SessionName>';
}
else {
    $URLStub .= 'customer.pl?<OTRS_CONFIG_CustomerPanelSessionName>';
}
$URLStub .= '=<OTRS_CONFIG_SessionID>';

$URLStub =~ s{<OTRS_CONFIG_([^>]+)>}{$URLConfigs{ $1 }}gxms;

print $URLStub ."\n";

exit 0;

1;
