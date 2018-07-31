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

set -e

# Setting variables
inLoc_1=1 # Location of 1st Bam
inLoc_2=1 # Location of 2nd Bam
readLen=0 # Read length, so we can calculate extension factor later
outputLoc="/tmp/" # Folder where to store all of the results
# TODO: 2 options>
isPE=false # Are the bams paired end?
debug=false # Is debug mode on?
# TODO: Nickname parameter? (instead of coverage[etc], cov_17767[etc] ... )

usage() { echo "Usage: $0 [-p|-l <0-200>] -a <input bam> -b <input bam> -o </tmp/>" 1>&2; exit 1;}
# Reusing some logic from runCount.sh
#   key points are: input (bam file), output (folder), l/p (paired or read length)
while getopts "h?pl:a:b:o:d" o; do
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
    a)
        inLoc_1=$OPTARG
        ;;
    b)
        inLoc_2=$OPTARG
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

# They must provide BAM file locations.
if [[ ${inLoc_1} == 1 ]]
then
    echo "BAM file 1 location must be provided."
    exit 1
fi

if [[ ${inLoc_2} == 1 ]]
then
    echo "BAM file 2 location must be provided."
    exit 1
fi

if [[ $isPE == true ]]
then
    args="-p"
else
    args="-l ${readLen}"
fi

run_pipeline ()
{
    ./runCount.sh ${args} -i ${1} -o ${outputLoc}${2}.wig
    ./fixCoverageFiles.sh -i ${outputLoc}${2}.wig -o ${outputLoc}${2}_processed.wig
    Rscript fitDistribution.R --input_loc ${outputLoc}${2}_processed.wig --output_loc ${outputLoc}${2}_p_value.wig
}

run_pipeline ${inLoc_1} coverage_a
run_pipeline ${inLoc_2} coverage_b

cor=$( Rscript findCorrelation.R --wig1 ${outputLoc}coverage_a_p_value.wig --wig2 ${outputLoc}coverage_b_p_value.wig )
echo ${cor}