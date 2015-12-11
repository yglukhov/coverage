# This is the main module for command-line cnimcoverage tool. This module
# should not be imported.

import coverage
import os

if getEnv("NIM_COVERAGE_DIR").len == 0:
    echo "NIM_COVERAGE_DIR environment variable not set"
    quit 1

createCoverageReport()
