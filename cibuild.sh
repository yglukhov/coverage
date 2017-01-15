set -e
nimble install -dy
cd tests
nake
cd -
