#!/bin/bash
# New version of Running IGVTools Count, without using python as a mediator.

set -e

# Something something make sure getopts will work properly
OPTIND=1

# Setting variables
BAMLoc=1 # Location of BAM
endSpecified=false
isPE=false # Is the BAM paired end?
readLen=0 # Read length, so we can calculate extension factor later
outputLoc="coverage.wig" # Output location
debug=false # Is debug mode on?
useCustomMemory=false
customMemoryAmt="1500m"
genome="hg19"
IGVFriendlyGenome="hg19"

# Usage string, to display on error or on -h
usage() { echo "Usage: $0 [-p|-l <0-200>] -i <input BAM location> -o <coverage.wig>" 1>&2; exit 1; }

# Parse variables
while getopts "h?pl:i:o:dx:m:g:" o; do
    case "${o}" in
	d)
	    debug=true
	    ;;
    p)
        endSpecified=true
        endArgs="--pairs"
        ;;
    h|\?)
        usage
        exit 0
        ;;
    i)
        BAMLoc=$OPTARG
        ;;
    l)
        endSpecified=true
        echo endArgs
        endArgs="-e $((200 - $OPTARG))"
        ;;
	o)
	    outputLoc=$OPTARG
	    ;;
    x)
        logLoc=$OPTARG
        ;;
    m)
        useCustomMemory=true
        customMemoryAmt=$OPTARG
        ;;
    g)
        genome=$OPTARG
        IGVFriendlyGenome="hg""${OPTARG: -2}" #IGV expects hg38, not grch38
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
	    usage
        exit 1
        ;;
    esac
done

# Either the BAM must be Paired End, or they must give us a read length so we can calculate
#	extension factor.
if [[ $endSpecified == false ]]
then
    echo "Either ReadLen or PairedEnd must be specified."
	exit 1
fi

# They must provide an BAM location.
if [[ ${BAMLoc} == 1 ]]
then
    echo "BAM file location must be provided."
    exit 1
fi

# If paired end, the above gives the parameter --pairs,
#	if single end, it gives the parameter -e [extension factor]

# If we are in debug mode, just print our command string.
if [[ $debug == true ]]
then
    # TODO : Return error code so we stop running?
    echo "igvtools count -w 5000 --minMapQuality 1 ${endArgs} ${BAMLoc} ${outputLoc} ${genome}"
    exit 0
fi
# Otherwise, actually run igvtools count.
if [[ $useCustomMemory == true ]]; then
    java -Xmx$customMemoryAmt -Djava.awt.headless=true -jar /usr/local/bin/igvtools.jar count -w 5000 --minMapQuality 1 ${args} ${BAMLoc} ${outputLoc} ${IGVFriendlyGenome} &>>${logLoc}runCount_log.txt
else
    igvtools count -w 5000 --minMapQuality 1 ${endArgs} ${BAMLoc} ${outputLoc} ${IGVFriendlyGenome} &>>${logLoc}runCount_log.txt
fi
exit 0