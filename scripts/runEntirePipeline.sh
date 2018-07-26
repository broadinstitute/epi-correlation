#!/bin/bash
# Runs the pipeline from start to finish.
# 1) Run IGVTools count
#       a) runCount.sh
# 2) Fix the output wig
#       a) fixCoverageFiles.sh
#           ^ calls guaranteeBins.R
# 3) Fit the distribution
#       a) FitDistribution.R
#           ^ calls a lot.

# Setting variables
inLoc=1 # Location of APP
readLen=0 # Read length, so we can calculate extension factor later
outputLoc="/output/" # Folder where to store all of the results
isPE=false # Is the APP paired end?
debug=false # Is debug mode on?

usage() { echo "Usage: $0 [-p|-l <0-200>] -i <input bam> -o </output/>" 1>&2; exit 1;}
# Reusing some logic from runCount.sh
#   key points are: input (bam file), output (folder), l/p (paired or read length)
while getopts "h?pl:i:o:d" o; do
    case "${o}" in
	d)
	    debug=true # Doesn't actually do anything at the moment.
	    ;;
    p)
        isPE=true
        ;;
    h|\?)
        usage
        exit 0
        ;;
    i)
        inLoc=$OPTARG
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

if [[ $isPE == true ]]
then
    args="-p"
else
    args="-l ${readLen}"
fi

./runCount.sh ${args} -i ${inLoc} -o ${outputLoc}coverage.wig
./fixCoverageFiles.sh -i ${outputLoc}coverage.wig -o ${outputLoc}coverage_processed.wig
Rscript fitDistribution.R --input_loc ${outputLoc}coverage_processed.wig --output_loc ${outputLoc}p_value.txt
