#!/bin/bash

inpWig=coverage.wig
outWig=coverage_processed.wig

# Usage string
usage() { echo "Usage: $0 [-i </reference/coverage.wig>] [-o </output/coverage_processed.wig]" 1>&2; exit 1; }

# Parsing Input
while getopts "h?i:o:" o; do
	case "${o}" in
		h|\?)
			usage
			exit 0
			;;
		i)
			inpWig=$OPTARG
			;;
		o)
			outWig=$OPTARG
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			usage
			exit 1
			;;
	esac
done


# Get all of the chromosome lines
lines=($( grep -n "chrom=" ${inpWig} | cut -d : -f 1))
# Add the end of the file, +1
lines+=($( wc -l ${inpWig} | cut -f 1 -d ' ' | awk '{ SUM = $1 + 1} END { print SUM }'))
chrs=($(grep -o -E -e 'chrom=chr[0-9|X|Y]+' ${inpWig}))

# Ensure tmp file doesn't already exist, since we append to it not rewrite it later
echo "" > ${inpWig}.tmp

# For every line between nth and n+1th chromosome lines, add chr[n] to the beginning.
for i in {0..24}
do
	prevLine=$(( ${lines[$i]}+1 ))
	nextLine=$(( ${lines[$((i + 1))]} - 1))
	curChr=${chrs[$i]##*=}
	sed -e "${prevLine},${nextLine}s/^/${curChr}\t/" ${inpWig} | awk "NR >= ${prevLine} && NR <= ${nextLine} {print} " >> ${inpWig}.tmp
done

Rscript guaranteeBins.R ${inpWig}.tmp ${outWig}
rm ${inpWig}.tmp
