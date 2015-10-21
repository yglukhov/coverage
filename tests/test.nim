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

proc toTest(x, y: int) {.cov.} =
    if x == 8:
        if y == 8:
            discard "This line should be covered"
        else:
            discard "This line should not be covered"
    else:
        discard "This line should be covered"

    if y == 5:
        discard "This line should be covered"

    if y == 6:
        discard "This line should not be covered"
    else:
        discard "This line should be covered"

toTest(8, 8)
toTest(5, 5)

sendCoverageResultsToCoveralls()
