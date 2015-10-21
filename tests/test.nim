import "../coverage"

proc test1(x: int) {.cov.} =
    if x == 0:
        echo "x is 0"
    else:
        echo "x is ", x

test1(0)

doAssert(totalCoverage() == 0.5)

test1(1)

doAssert(totalCoverage() == 1.0)
