#!/usr/bin/perl
# --
# bin/znuny.ITSMConfigItemsDeleteAfterDate.pl - deletes ITSM ConfigItems that are newer than a given date
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
use Kernel::System::Encode;
use Kernel::System::Time;
use Kernel::System::Log;
use Kernel::System::Main;
use Kernel::System::DB;
use Kernel::System::ITSMConfigItem;

use Kernel::System::VariableCheck qw(:all);

# get options
my %Opts;
GetOptions(
    'date|d=s' => \$Opts{NewerThanDate},
    'help|h'   => \$Opts{Help},
);

# common objects
my %CommonObject;
$CommonObject{ConfigObject} = Kernel::Config->new();
$CommonObject{EncodeObject} = Kernel::System::Encode->new(%CommonObject);
$CommonObject{LogObject}    = Kernel::System::Log->new(
    LogPrefix => 'OTRS-znuny.ITSMConfigItemsDeleteAfterDate.pl',
    %CommonObject,
);
$CommonObject{TimeObject}       = Kernel::System::Time->new(%CommonObject);
$CommonObject{MainObject}       = Kernel::System::Main->new(%CommonObject);
$CommonObject{DBObject}         = Kernel::System::DB->new(%CommonObject);
$CommonObject{ConfigItemObject} = Kernel::System::ITSMConfigItem->new(%CommonObject);

if (
    !IsStringWithData( $Opts{NewerThanDate} )
    || $Opts{NewerThanDate} !~ m{\d{4}-\d{2}-\d{2} \s \d{2}:\d{2}:\d{2}}xms
    || $Opts{Help}
) {
    print STDOUT "znuny.ITSMConfigItemsDeleteAfterDate.pl - deletes ITSM ConfigItems that are newer than a given date\n";
    print STDOUT "Copyright (C) 2014 Znuny GmbH, http://znuny.com/\n";
    print STDOUT "usage: znuny.ITSMConfigItemsDeleteAfterDate.pl

Required parameters:
    -[-d]ate  - the date after which all ITSM ConfigItems should get deleted, format is '2014-08-12 09:00:00'

Optional parameters:
    -[-h]elp    - print this help text\n";
    exit 0;
}

# ask database
$CommonObject{DBObject}->Prepare(
    SQL  => "SELECT ci.id FROM configitem ci WHERE ci.create_time > ?",
    Bind => [ \$Opts{NewerThanDate} ],
);

# fetch the result
my @ConfigItemIDs;
while ( my @Row = $CommonObject{DBObject}->FetchrowArray() ) {
    push @ConfigItemIDs, $Row[0];
}

if ( !scalar @ConfigItemIDs ) {
    print STDOUT "No ConfigItems affected. Exiting.\n";
    exit 0;
}

print STDOUT (scalar @ConfigItemIDs) . " ConfigItems affected...\n";

CI:
for my $ConfigItemID ( sort @ConfigItemIDs ) {

    print STDOUT "Deleting ConfigItem with ConfigItemID '$ConfigItemID'.\n";

next CI;

    my $Success = $CommonObject{ConfigObject}->ConfigItemDelete(
        ConfigItemID => $ConfigItemID,
        UserID       => 1,
    );

    next CI if $Success;

    $CommonObject{LogObject}->Log(
        Priority => 'error',
        Message  => "Error while deleting ConfigItem with ConfigItemID '$ConfigItemID'.",
    );
}

exit 0;
1;
