#!perl

# The PureStorage probe was created using a file-size checker perl probe
# as a baseline.  Code from that probe is still present in this probe. 
# If i find the file size checker probe I will try to include it in this 
# repository and scrape out the elements from this code for ease of reading.
# - Devin Roark

# Main PureStorage subroutines here are
# purestoreage_query
#   - makes connection to the REST API
#   - runs query against each table and writes to JSON
# purestorage_monitor
#   - Cycles through JSON and sends CI, QoS, and Alarms

#use lib "c:\\program files (x86)\\nimsoft\\perllib\\";

use Nimbus::API;
use Nimbus::CFG;
use Nimbus::Session;
use Nimbus::PDS;

#purestorage

use REST::Client;
use JSON;
use  HTTP::Cookies;

# Data::Dumper makes it easy to see what the JSON returned actually looks like
# when converted into Perl data structures.
use Data::Dumper;
use MIME::Base64;

$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

## end


my $prgname = "PureStorage_VolumeSize";
my $qosDefinition = 0;
my $filesize = 0;
my $source = "darst021";
my $next_run = time();
my $alarmId = 0;
my $rc = 0;

my $config   = "";
my $loglevel =  2;
my $logfile  = "$prgname.log";
my $filename = "$prgname.txt";
my $interval = 60;
my $filethreshold = 2000;

sub purestorage_query{

my $cookies = HTTP::Cookies->new();
my $ua = LWP::UserAgent->new( cookie_jar => $cookies );
my $headers = {Content-type => 'application/json'};
my $client = REST::Client->new( { useragent => $ua });


$client->setHost('https://sjc-purestorage1.gecis.io');

#https://sjc-purestorage1.gecis.io/api/1.3/volume/SJC-BLK-BOS-CFMGT?space=true

$client->POST( '/api/1.3/auth/session' , '{ "api_token" : "foo" }', {"Content-type" => 'application/json'} );

$client->GET( '/api/1.3/volume/SJC-BLK-BOS-CFMGT?space=true' );



   my $response = from_json($client->responseContent());

    print Dumper($response);
    print $response->{size};

#   $client->GET('/api/1.3/array?controllers=true');

 #   print Dumper($client->responseContent());


	return $response;
}


###########################################################
# Command-set callback function(s), with parameter transfer
#
sub get_size {
	my ($hMsg,$arg1,$arg2,$arg3) = @_;
    my $reply = pdsCreate();
    nimLog(2, "[get_size] INFO: Sending request filesize $filesize");
    pdsPut_INT($reply,"filesize",$filesize);
    nimSendReply($hMsg,0,$reply);
    pdsDelete($reply);
}

###########################################################
# DoWork - function called by dispatcher on timeout
#
sub doWork {
		
    my $now = time();
    return if ($now < $next_run);
    $next_run = $now + $interval;
    
#    my @myFiles = ( $filename, "fileSizeCheck.log");
    
#    foreach (@myFiles) {
#	    monitor_file($_);
#    }    

   my $volume = purestorage_size(); 

   monitor_purestorage($volume);

    nimLog(0, "[doWork] INFO: Writing to file: $filename");
	open (MYFILE, '>>genesys_filesize.txt');
	print MYFILE "A test for genesys\n";
	close (MYFILE);
}

sub purestorage_monitor {
	
	my $volume = shift;
	my $token  = "cp#$prgname";                  # usage of token is still unknown
    my $pds    = new Nimbus::PDS();
    $pds->string($volume->{name});

# check from mysql CMConfiguration
	print Dumper($volume);
	#my $pCI = ciOpenRemoteDevice ("5.14",$volume->{name},"sjc-purestorage1.gecis.io");
	my $pCI = ciOpenLocalDevice ("5.14", "hello");
      
       print "pCI is $pCI";
#    nimLog(0, "[doWork] INFO: $source: $file: pCI: $pCI");
    
	# My code	
    
    if (my $qos = nimQoSCreate("QOS_VOLUMESIZE",$source,$interval,-1)) {
	print "qos is $qos";
	    ciBindQoS($pCI,$qos,"5.14:11");
        if ($volume->{size} < 0) {
            nimQoSSendNull ($qos,$volume->{name});
        } else {
	        nimQoSSendValueStdev($qos,$volume->{name},$volume->{size}/(1024*1024),0);
        }
        nimLog(0,"[doWork] INFO: Publish $volume->{name}, $volume->{size}/(1024*1024)");
        ciUnBindQoS($pCI);
        nimQoSFree($qos);
    }
    ciClose($pCI);
}

sub monitor_file {

	
	my $file = shift;
	my $token  = "cp#$prgname";                  # usage of token is still unknown
    my $pds    = new Nimbus::PDS();
    $pds->string("geheim","ach wie gut dass niemand weiss ...");

	my $pCI = ciOpenLocalDevice ("1.10",$file);
    nimLog(0, "[doWork] INFO: $source: $file: pCI: $pCI");
    
	# My code	
	unless (-e $file) {
 		$filesize = -1;
 		($rc,$alarmId) = ciAlarm($pCI,"1.10:18",5,"File $file does not exist",$token, $pds->data(),"1.10","$prgname $file file_exist","$source");
        nimLog(2, "[doWork] ERROR: File $file does not exist ($alarmId)");
 	} else {
	 	($rc,$alarmId) = ciAlarm($pCI,"1.10:18",0,"File $file does exist",$token, $pds->data(),"1.10","$prgname $file file_exist","$source");
	    $filesize = -s $file;
	    
	    if ($filesize >= $filethreshold) {
		    nimLog(0, "[doWork] INFO: Problem with file size: $file");
		    ($rc,$alarmId) = ciAlarm($pCI,"1.10:18",5,"File $file size $filesize has exceeded threshold of $filethreshold",$token, $pds->data(),"1.10","$prgname $file threshold_exceed","$source");            
		    nimLog(2, "[doWork] ERROR: File $file size $filesize has exceeded threshold of $filethreshold ($alarmId)");
		    if ($file eq "genesys_filesize.txt" ) {
			    nimLog(0, "[doWork] INFO: Resetting file: $file");
				open (MYFILE, '>genesys_filesize.txt');
				print MYFILE "A test for genesys\n";
				close (MYFILE);
		    }
	    } else {
		    ($rc,$alarmId) = ciAlarm($pCI,"1.10:18",0,"File $file size $filesize is within threshold of $filethreshold",$token, $pds->data(),"1.10","$prgname $file threshold_exceed","$source");
		    nimLog(2, "[doWork] INFO: File $file size $filesize is within threshold of $filethreshold ($alarmId)");
	    }
	}
    
    if (my $qos = nimQoSCreate("QOS_FILESIZE",$source,$interval,-1)) {
	    ciBindQoS($pCI,$qos,"1.10:18");
        if ($filesize < 0) {
            nimQoSSendNull ($qos,$file);
        } else {
	        nimQoSSendValueStdev($qos,$file,$filesize,0);
        }
        nimLog(0,"[doWork] INFO: Publish $file, $filesize");
        ciUnBindQoS($pCI);
        nimQoSFree($qos);
    }
    ciClose($pCI);
}

#######################################################################
# Service functions
#
sub restart {
}

sub timeout {
    doWork();
}

###########################################################
# Signal handler - Ctrl-Break
#
sub ctrlc {

    nimLog(0,"Got a control-C so am restarting");
    exit;
}

###########################################################
# MAIN ENTRY
#

$SIG{INT} = \&ctrlc;

$config   = Nimbus::CFG->new("$prgname.cfg");
$loglevel = $config->{setup}->{loglevel}|| 2;
$logfile  = $config->{setup}->{logfile} || "$prgname.log";
$filename = $config->{setup}->{filename} || "$prgname.txt";
$interval = $config->{setup}->{interval} || 60;
$filethreshold = $config->{setup}->{file_threshold} || 2000;

nimLogSet($logfile,$prgname,$loglevel,0);
nimLog(0,"----------------- Starting  (pid: $$) ------------------");

	nimLog(2, "[main] INFO: Config file: $prgname.cfg");
	nimLog(2, "[main] INFO: log level: $loglevel");
	nimLog(2, "[main] INFO: filename: $filename");
	nimLog(2, "[main] INFO: interval: $interval");
	nimLog(2, "[main] INFO: threshold: $filethreshold");
	
	nimLog(2, "[main] INFO: Defining QoS definition");
	# Send the QoS Definition 
    nimQoSSendDefinition ("QOS_VOLUMESIZE",       # QOS Name
                          "QOS_VOLUME",       	# QOS Group
                          "Volume size",   		# QOS Description
                          "Gigabytes","GB");         # QOS Unit and Abbreviation

	$sess = Nimbus::Session->new("$prgname");
	$sess->setInfo($version,"Nimsoft Software AS");
	
	if ($sess->server (NIMPORT_ANY,\&timeout,\&restart)==0) {
	    $sess->addCallback ("get_size");
	}else {
	    nimLog(0,"unable to create server session");
	    exit(1);
	}
	
	nimLog(0,"Going to dispatch the probe");
	
	$sess->dispatch();
	exit;
