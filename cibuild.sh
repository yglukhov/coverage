set -e
nimble install -y
cd tests
nake
cd -
