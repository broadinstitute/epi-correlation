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
tmpLoc="/tmp/" # Folder where to store all of the midway files (i.e. coverage.wig, coverage_processed.wig.PARAMS)
outLoc="/data/output"
logLoc="/data/logs"
# TODO: 2 options>
isPE=false # Are the bams paired end?
debug=false # Is debug mode on?
checkPermissions=true
# TODO: Nickname parameter? (instead of coverage[etc], cov_17767[etc] ... )

# Test for being able to read/write to /data
if [[ checkPermisions == false ]]
then
    permissions=$( stat -c "%A" /data )
    permissions_all=${permissions:4:3}
    if [[ $permissions_all != "rwx" ]]
    then
        echo "ERROR: Do not have read/write permissions to data folder."
        exit 1
    fi
fi

usage() { echo "Usage: $0 [-p|-l <0-200>] -a <input bam> -b <input bam> -m </tmp/> [-o <>] [-s]" 1>&2; exit 1;}
# Reusing some logic from runCount.sh
#   key points are: input (bam file), output (folder), l/p (paired or read length)
while getopts "h?pl:a:b:m:do:sc" o; do
    case "${o}" in
	d)
	    debug=true
	    ;;
    p)
        isPE=true
        ;;
    s)
        silenceAllButCorToSTDOUT=true
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
	m)
	    tmpLoc=$OPTARG
	    ;;
    o)
        outLoc=$OPTARG
        ;;
    c)
        checkPermissions=false
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

check_for_bais ()
{
    if [[ ! -f ${1}.bai  && ! -f ${1%.*}.bai ]]; then
        if [[ $debug == true ]]; then echo "Creating index file for ${1}"; fi
        igvtools index ${1} > /tmp/indexLog.txt
    fi
}

run_pipeline ()
{
    # Check if bam files are indexed

    if [[ $debug == true ]]; then echo "Running IGVTools Count for ${1}; saving to ${2}"; fi
    /scripts/runCount.sh ${args} -i ${1} -o ${tmpLoc}${2}.wig

    if [[ $debug == true ]]; then echo "Fixing Coverage File ${2}"; fi
    /scripts/fixCoverageFiles.sh -i ${tmpLoc}${2}.wig -o ${tmpLoc}${2}_processed.wig

    if [[ $debug == true ]]; then echo "Fitting distribution to ${2}"; fi
    Rscript /scripts/fitDistribution.R --input_loc ${tmpLoc}${2}_processed.wig --output_loc ${tmpLoc}${2}_p_value.wig

    if [[ $debug == true ]]; then echo "Fitting pipeline complete on $1"; fi
}

check_for_bais ${inLoc_1} & check_for_bais ${inLoc_2} & wait
run_pipeline ${inLoc_1} coverage_a & run_pipeline ${inLoc_2} coverage_b & wait

cor=$( Rscript /scripts/findCorrelation.R --wig1 ${tmpLoc}coverage_a_p_value.wig --wig2 ${tmpLoc}coverage_b_p_value.wig )
echo ${cor} > $outLoc"cor_out.txt"
if [[ $debug == false ]]; then echo $cor; exit 0; fi
echo "Final correlation between ${inLoc_1} & ${inLoc_2}: ${cor}"
