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
outLoc="/data/output/"
logLoc="/data/logs/"
# TODO: 2 options>
isPE=false # Are the bams paired end?
debug=false # Is debug mode on?
checkPermissions=true
singleThreaded=false
# TODO: Nickname parameter? (instead of coverage[etc], cov_17767[etc] ... )

usage() { echo "Usage: $0 [-p|-l <0-200>] -a <input bam> -b <input bam> -t </tmp/> [-o </data/output>] [-x </data/logs>] [-d]" 1>&2; exit 1;}
# Reusing some logic from runCount.sh
#   key points are: input (bam file), output (folder), l/p (paired or read length)
while getopts "h?pl:a:b:do:cx:t:s" o; do
    case "${o}" in
	d)
	    debug=true
	    ;;
    p)
        isPE=true
        ;;
    s)
        singleThreaded=true
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
        outLoc=$OPTARG
        ;;
    t)
        tmpLoc=$OPTARG
        ;;
    x)
        logLoc=$OPTARG
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

# Test for being able to read/write to /data.
# $checkPermissions should only ever be set to false when we are using non-mounted data; i.e. testPipeline.sh, which has its own folders & data and doesn't have to worry about permissions.
if [[ $checkPermissions == true ]]
then
    permissions=$( stat -c "%A" /data )
    permissions_all=${permissions:7:3}
    # I am literally stripping out the last 3 characters of the human-readable permissions string, representing permissions for all users.
    if [[ $permissions_all != "rwx" ]]
    then
        echo "ERROR: Do not have read/write permissions to the provided data folder."
        echo "Please run chmod a+w to your data folder."
        exit 1
    fi
fi

# Make sure all of the directories exist.
if [ ! -d "$tmpLoc" ]; then
    mkdir $tmpLoc
fi
if [ ! -d "$logLoc" ]; then
    mkdir $logLoc
fi
if [ ! -d "$outLoc" ]; then
    mkdir $outLoc
fi
# TODO : do we want to make sure that they user had a "/" at the end? Otherwise, things don't actually get put into the directory they specify. On the other hand, that's babysitting.
# TODO : How do we go about making sure that all of the files output by the docker are delete-able by the user?

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

# If it's paired end, we want to append -p, if it's not, we want to append -l and the read length to later commands.
if [[ $isPE == true ]]
then
    args="-p"
else
    args="-l ${readLen}"
fi

# If the files aren't indexed, index them.
check_for_bais ()
{
    if [[ ! -f ${1}.bai  && ! -f ${1%.*}.bai ]]; then
        if [[ $debug == true ]]; then echo "Creating index file for ${1}"; fi
        igvtools index ${1} > ${logLoc}indexLog.txt
    fi
}

run_pipeline ()
{
    # Comments are in the debug statements.
    if [[ $debug == true ]]; then echo "Running IGVTools Count for ${1}; saving to ${2}"; fi
    /scripts/runCount.sh ${args} -i ${1} -o ${tmpLoc}${2}.wig -x ${logLoc}

    if [[ $debug == true ]]; then echo "Fixing Coverage File ${2}"; fi
    /scripts/fixCoverageFiles.sh -i ${tmpLoc}${2}.wig -o ${tmpLoc}${2}_processed.wig

    if [[ $debug == true ]]; then echo "Fitting distribution to ${2}"; fi
    Rscript /scripts/fitDistribution.R --input_loc ${tmpLoc}${2}_processed.wig --output_loc ${tmpLoc}${2}_p_value.wig

    if [[ $debug == true ]]; then echo "Fitting pipeline complete on $1"; fi
}

# I have a theory that trying to run in parallel causes extreme slow-down in single-core machines.
# Allowing toggling of single-threaded mode to test this.
if [[ singleThreaded == true ]]
then
    check_for_bais ${inLoc_1}
    check_for_bais ${inLoc_2}

    run_pipeline ${inLoc_1} coverage_a
    run_pipeline ${inLoc_2} coverage_b
else
    check_for_bais ${inLoc_1} & check_for_bais ${inLoc_2} & wait

    run_pipeline ${inLoc_1} coverage_a & run_pipeline ${inLoc_2} coverage_b & wait
fi
# Finally, calculate correlation.
cor=$( Rscript /scripts/findCorrelation.R --wig1 ${tmpLoc}coverage_a_p_value.wig --wig2 ${tmpLoc}coverage_b_p_value.wig )

# Save the correlation to a file.
echo ${cor} > $outLoc"cor_out.txt"

# If we're not in debug mode, just print out the correlation & quit.
if [[ $debug == false ]]; then echo $cor; exit 0; fi

# Otherwise, make it pretty.
echo "Final correlation between ${inLoc_1} & ${inLoc_2}: ${cor}"
