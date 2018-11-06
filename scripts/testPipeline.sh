#!/bin/bash

# Copy over our BAM files to somewhere we can mess with them.
cp /test_data/*.bam .

# Test data is of format TEST_A.bam & TEST_B.bam.
differentFiles=$(/scripts/runEntirePipeline.sh -p --skip-readwrite-check --bam-a TEST_A.bam --bam-b TEST_B.bam)
sameFiles=$(/scripts/runEntirePipeline.sh -p --skip-readwrite-check -a TEST_A.bam -b TEST_A.bam)
mintFiles=$(/scripts/runEntirePipeline.sh --skip-readwrite-check --mint -a TEST_A.bam -b TEST_B.bam)
grch38Files=$(/scripts/runEntirePipeline.sh --skip-readwrite-check --genome grch38 -a TEST_A.bam -b TEST_B.bam)

echo "Pipeline testing results: "
echo "File A vs File A: "
echo -n ${sameFiles}; echo -n "     "
if [[ ${sameFiles} =~ "1" ]]; then
  echo "Pass"
else
  echo "Fail; LOG:"; echo -n "     "
  echo "$(cat /data/logs/*)"
  exit 1
fi
echo

echo "File A vs File B: "
echo -n ${differentFiles}; echo -n "     "
if [[ ${differentFiles} =~ "-0.652163" ]]; then
  echo "Pass"
else
  echo "Fail; LOG:"; echo -n "     "
  echo "$(cat /data/logs/*)"
  exit 1
fi

echo "File A vs File B (flagged mint): "
echo -n ${mintFiles}; echo -n "     "
if [[ ${mintFiles} =~ "-0.6534215" ]]; then
  echo "Pass"
else
  echo "Fail; LOG:"; echo -n "     "
  echo "$(cat /data/logs/*)"
  exit 1
fi

echo "File A vs File B (flagged grch38): "
echo -n ${grch38Files}; echo -n "     "
if [[ ${grch38Files} =~ "-0.6503286" ]]; then
  echo "Pass"
else
  echo "Fail; LOG:"; echo -n "     "
  echo "$(cat /data/logs/*)"
  exit 1
fi
