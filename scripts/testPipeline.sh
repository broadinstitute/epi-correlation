#!/bin/bash

# Copy over our BAM files to somewhere we can mess with them.
cp /test_data/*.bam /tmp/

# Test data is of format TEST_A.bam & TEST_B.bam.
differentFiles=$(/scripts/runEntirePipeline.sh -p -a /tmp/TEST_A.bam -b /tmp/TEST_B.bam -s)
sameFiles=$(/scripts/runEntirePipeline.sh -p -a /tmp/TEST_A.bam -b /tmp/TEST_A.bam -s)
echo "Pipeline testing results: "
echo "File A vs File A: "
echo -n ${sameFiles}; echo -n "     "; [[ ${sameFiles} =~ "1" ]] && echo "Pass" || echo "Fail"
echo
echo "File A vs File B: "
echo -n ${differentFiles}; echo -n "     "; [[ ${differentFiles} =~ "-0.652163" ]] && echo "Pass" || echo "Fail"
