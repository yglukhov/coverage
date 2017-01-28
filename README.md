# coverage [![Build Status](https://travis-ci.org/yglukhov/coverage.svg?branch=master)](https://travis-ci.org/yglukhov/coverage) [![Coverage Status](https://coveralls.io/repos/yglukhov/coverage/badge.svg?branch=master&service=github)](https://coveralls.io/github/yglukhov/coverage?branch=master)
Code coverage library for Nim. Inspired by [Andreas Rumpf talk at OSCON](https://github.com/Araq/oscon2015).

## Usage
```nim
import coverage
import tables

proc myProcToCover(x: int) {.cov.} = # Add cov pragma to proc definition to enable code coverage.
  if x == 0:
    echo "x is 0"
  else:
    echo "x is ", x

# Run your program or unittest
myProcToCover(1)

# At the end of the program, display coverage results:
echo "BY FILE: "
for fname, perc in coveragePercentageByFile():
  echo fname, " ", perc
# Outputs: BY FILE: {test.nim: 0.5}

echo "TOTAL: ", totalCoverage()
# Outputs: TOTAL: 0.5

# Finer grained information may be accessed with coverageInfoByFile proc.
```

### Adding coverage to a unittest file
```nim
import coverage, tables, unittest

# Import your code and run the tests as usual
# suite "test": ...

echo "Coverage by file: "
for fname, num in coveragePercentageByFile().pairs():
  echo fname, " ", num

echo "Total coverage: ", totalCoverage()
```

Add "import coverage" and the top of your sources and add "{.cov.}" to every proc.


### Generating a report
```bash
export NIM_COVERAGE_DIR=coverage_results
mkdir -p "$NIM_COVERAGE_DIR"

nim c -r your_tests.nim
nimcoverage genreport
```

### Notes
- Code coverage is disabled if ```release``` is defined. Define ```enableCodeCoverage``` option to keep it enabled in release mode.

# Travic CI + Coveralls integration
If you're using [Travis CI](https://travis-ci.org) and [Coveralls](https://coveralls.io), you can upload coverage results right at the end of your program:
```nim
sendCoverageResultsToCoveralls()
```
