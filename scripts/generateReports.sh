#!/bin/bash

set -e

INPUTS="$1"
OUTPUT_DIR="$2"

# TODO:
# run an actual reporting script
# that generates
# ordered report.tsv and report.pdf
# from ${INPUTS}.
# Example columns for report.tsv:
# nameA   nameB   corr  group
cp "${INPUTS}" report.tsv
touch report.pdf

gsutil cp report.* "${OUTPUT_DIR}/"
