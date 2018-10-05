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
umask ugo=rwx

# Setting variables
inLoc_1=1 # Location of 1st Bam
inLoc_2=1 # Location of 2nd Bam
tmpLoc="/tmp/" # Folder where to store all of the midway files (i.e. coverage.wig, coverage_processed.wig.PARAMS)
outLoc="/data/output/"
logLoc="/data/logs/"
# TODO: 2 options>
debug=false # Is debug mode on?
checkPermissions=true
singleThreaded=false
useCustomMemory=false
customMemoryAmt="1500m"
# Paired vs Single End parameters
endSpecified=false # set to true if they give us info
endArgs="" # set to -p or -l <n>
# TODO: Nickname parameter? (instead of coverage[etc], cov_17767[etc] ... )

usage() { echo "Usage: $0 [-p|-l <0-200>] -a <input bam> -b <input bam> [-t </tmp/>] [-o </data/output>] [-x </data/logs>] [-d] [-m [0-9]+(m|g)]" 1>&2; exit 1;}
# Reusing some logic from runCount.sh
#   key points are: input (bam file), output (folder), l/p (paired or read length)
while getopts "h?pl:a:b:do:cx:t:sm:" o; do
    case "${o}" in
	d)
	    debug=true
	    ;;
    p)
        endSpecified=true
        endArgs="-p"
        ;;
    l)
        endSpecified=true
        endArgs="-l ${OPTARG}"
        ;;
    s)
        singleThreaded=true
        ;;
    h|\?)
        usage
        exit 0
        ;;
    a)
        inLoc_1="/data/"$OPTARG
        ;;
    b)
        inLoc_2="/data/"$OPTARG
        ;;
    o)
        if [[ ! ${OPTARG: -1} == "/" ]]; then
            OPTARG=${OPTARG}"/"
        fi
        outLoc=$OPTARG
        ;;
    t)
        if [[ ! ${OPTARG: -1} == "/" ]]; then
            OPTARG=${OPTARG}"/"
        fi
        tmpLoc=$OPTARG
        ;;
    x)
        if [[ ! ${OPTARG: -1} == "/" ]]; then
            OPTARG=${OPTARG}"/"
        fi
        logLoc=$OPTARG
        ;;
    c)
        checkPermissions=false
        ;;
    m)
        useCustomMemory=true
        customMemoryAmt=$OPTARG
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
	    usage
        exit 1
        ;;
    esac
done

# Test if data directory exists.
# Technically may be no longer necessary, as the docker automatically
#   sets WORKDIR to /data, thus creating it. I don't want to play with
#   it though. Too many changes happening right now.
if [ ! -d "/data" ]; then
    echo "ERROR: No data directory. Did you forget to mount it?"
    exit 1
fi

# Test if there's anything in the data directory.
if [ ! "$(ls -A /data)" ]; then
    echo "ERROR: Empty data directory. Did you mount the right directory?"
    exit 1
fi

# Test for being able to read/write to /data.
# $checkPermissions should only ever be set to false when we are using non-mounted data; i.e. testPipeline.sh, which has its own folders & data and doesn't have to worry about permissions.
# TODO : turn this into a function so we can call it on the tmploc, logloc, & outloc
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

# Count the number of paired end reads. If > 0, means this is PE data.
check_if_paired_end ()
{
    n_paired_lines=$( samtools view -c -f 1 $1 )
    if (( $n_paired_lines > 0 )); then
        echo true
    else
        echo false
    fi
}

# Take the length of the first 10k reads and find the average
find_average_read_length ()
{
    avg=$( samtools view $1 | awk '{print length($10)}' | head -10000 | sort -u | awk '{s+=$1} END {print s/NR}' )
    echo avg
}

# If the files aren't indexed, index them.
check_for_bais ()
{
    if [[ ! -f ${1}.bai  && ! -f ${1%.*}.bai ]]; then
        if [[ $debug == true ]]; then echo "Creating index file for ${1}"; fi
        if [[ $useCustomMemory == true ]]; then
            java -Xmx$customMemoryAmt -Djava.awt.headless=true -jar /usr/local/bin/igvtools.jar index ${1} > ${logLoc}indexLog.txt
        else
            igvtools index ${1} > ${logLoc}indexLog.txt
        fi
    fi
}

run_pipeline ()
{
    # Comments are in the debug statements.
    if [[ $debug == true ]]; then echo "Running IGVTools Count for ${1}; saving to ${2}"; fi

    # TODO : fold this into the args construction below.
    countParam=""
    if [[ $useCustomMemory == true ]]; then
        countParam="-m ${customMemoryAmt}"
    fi

    # If the user hasn't told us whether or not it's paired end...
    # Automatically determine whether the BAM is paired end
    #   if not, find the average read length
    if [[ $endSpecified == false ]]; then
        isPaired=$(check_if_paired_end ${1})
        if [[ $isPaired == true ]]; then
            endArgs="-p"
        else
            len=$( find_average_read_length ${1} )
            endArgs="-l "$len
        fi
    fi

    /scripts/runCount.sh ${endArgs} -i ${1} -o ${tmpLoc}${2}.wig -x ${logLoc} ${countParam}

    if [[ $debug == true ]]; then echo "Fixing Coverage File ${2}"; fi
    /scripts/fixCoverageFiles.sh -i ${tmpLoc}${2}.wig -o ${tmpLoc}${2}_processed.wig

    if [[ $debug == true ]]; then echo "Fitting distribution to ${2}"; fi
    Rscript /scripts/fitDistribution.R --input_loc ${tmpLoc}${2}_processed.wig --output_loc ${tmpLoc}${2}_p_value.wig

    if [[ $debug == true ]]; then echo "Fitting pipeline complete on $1"; fi
}

# Allows the user to run all commands in series rather than attempting
#   to do a few in parallel.
if [[ $singleThreaded == true ]]
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
