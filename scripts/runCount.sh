#!/bin/bash
# New version of Running IGVTools Count, without using python as a mediator.

# Something something make sure getopts will work properly
OPTIND=1

# Setting variables
APPLoc=1 # Location of APP
readLen=0 # Read length, so we can calculate extension factor later
outputLoc="coverage.wig" # Output location
isPE=false # Is the APP paired end?
debug=false # Is debug mode on?

# Usage string, to display on error or on -h
usage() { echo "Usage: $0 [-p|-l <0-200>] -a <input APP location> -o <coverage.wig>" 1>&2; exit 1; }

# Parse variables
while getopts "h?pl:a:o:d" o; do
    case "${o}" in
	d)
	    debug=true
	    ;;
    p)
        isPE=true
        ;;
    h|\?)
        usage
        exit 0
        ;;
    a)
        APPLoc=$OPTARG
        ;;
    l)
        readLen=$OPTARG
        ;;
	o)
	    outputLoc=$OPTARG
	    ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
	    usage
        exit 1
        ;;
    esac
done

# Either the APP must be Paired End, or they must give us a read length so we can calculate
#	extension factor.
if (( $readLen <= 0 )) && [[ $isPE == false ]]
then
	echo "ReadLen must provided if the APP is not Paired End."
	exit 1
fi

# They must provide an APP location.
if [[ ${APPLoc} == 1 ]]
then
    echo "BAM file location must be provided."
    exit 1
fi

# Our usual is to extend all reads by 200-read length, which is what is calculated below.
adjstAmnt=$((200-readLen))
args="-e $adjstAmnt"
# If this is paired end, change to --pairs.
($isPE) && args='--pairs'
# If paired end, the above gives the parameter --pairs, 
#	if single end, it gives the parameter -e [extension factor]

# If we are in debug mode, just print our command string.
if [[ $debug == true ]]
then
    echo "igvtools count -w 5000 --minMapQuality 1 ${args} ${APPLoc} ${outputLoc} hg19"
    exit 0
fi
# Otherwise, actually run igvtools count.
igvtools count -w 5000 --minMapQuality 1 ${args} ${APPLoc} ${outputLoc} hg19
exit 0
