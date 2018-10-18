#!/bin/bash

# Copy over our BAM files to somewhere we can mess with them.
cp /test_data/*.bam .

# Test data is of format TEST_A.bam & TEST_B.bam.
differentFiles=$(/scripts/runEntirePipeline.sh -p -a TEST_A.bam -b TEST_B.bam -c)
sameFiles=$(/scripts/runEntirePipeline.sh -p -a TEST_A.bam -b TEST_A.bam -c)
echo "Pipeline testing results: "

echo "File A vs File A: "
echo -n ${sameFiles}; echo -n "     "
if [[ ${sameFiles} =~ "1" ]]; then
  echo "Pass"
else
  echo "Fail"
  exit 1
fi
echo

echo "File A vs File B: "
echo -n ${differentFiles}; echo -n "     "
if [[ ${differentFiles} =~ "-0.652163" ]]; then
  echo "Pass"
else
  echo "Fail"
  exit 1
fi
