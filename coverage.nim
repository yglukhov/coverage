import macros
import tables
import strutils

proc fileName(n: NimNode): string =
    let ln = n.lineinfo
    let i = ln.rfind('(')
    result = ln.substr(0, i - 1)

proc lineNumber(n: NimNode): int =
    let ln = n.lineinfo
    let i = ln.rfind('(')
    let j = ln.rfind(',')
    result = parseInt(ln.substr(i + 1, j - 1))

type CovData* = tuple[lineNo: int, passed: bool]
var coverageResults* = newSeq[tuple[fileName: cstring, data: ptr seq[CovData]]]()

proc transform(n, track, list: NimNode): NimNode {.compileTime.} =
    result = copyNimNode(n)
    for c in n.children:
        result.add c.transform(track, list)

    if n.kind in {nnkElifBranch, nnkOfBranch, nnkExceptBranch, nnkElse}:
        let lineno = result[^1].lineNumber

        template trackStmt(track, i) =
            track[i].passed = true

        result[^1] = newStmtList(getAst trackStmt(track, list.len), result[^1])
        template tup(lineno) =
              (lineno, false)
        list.add(getAst tup(lineno))

macro cov*(body: untyped): untyped =
    when defined(release) and not defined(enableCodeCoverage):
        result = body
    else:
        let file = body.fileName
        var trackSym = genSym(nskVar, "track")
        var trackList = newNimNode(nnkBracket)
        var listVar = newStmtList(
            newNimNode(nnkVarSection).add(
                newNimNode(nnkIdentDefs).add(trackSym, newNimNode(nnkBracketExpr).add(newIdentNode("seq"), newIdentNode("CovData")), prefix(trackList, "@"))),
            newCall("add", newIdentNode("coverageResults"), newPar(newCall("cstring", newStrLitNode(file)), newCall("addr", trackSym)))
            )

    result = transform(body, trackSym, trackList)
    result = newStmtList(listVar, result)

proc coverageInfoByFile*(): Table[string, tuple[linesTracked, linesCovered: int]] =
    result = initTable[string, tuple[linesTracked, linesCovered: int]]()
    for cr in coverageResults:
        let fn = $(cr.fileName)
        var (linesTracked, linesCovered) = result.getOrDefault(fn)
        for c in cr.data[]:
            inc linesTracked
            if c.passed: inc linesCovered
        result[fn] = (linesTracked, linesCovered)

proc coveragePercentageByFile*(): Table[string, float] =
    result = initTable[string, float]()
    for k, v in coverageInfoByFile():
        result[k] = v.linesCovered.float / v.linesTracked.float

proc totalCoverage*(): float =
    var linesTracked = 0
    var linesCovered = 0
    for cr in coverageResults:
        for c in cr.data[]:
            inc linesTracked
            if c.passed: inc linesCovered
    result = linesCovered.float / linesTracked.float

when isMainModule:
    proc toTest(x, y: int) {.cov.} =
      try:
        case x
        of 8:
          if y > 9: echo "8.1"
          else: echo "8.2"
        of 9: echo "9"
        else: echo "foo"
        echo "no exception"
      except IoError:
        echo "IoError"

    proc toTest2(x: int) {.cov.} =
        if x == 0:
            echo "x is 0"
        else:
            echo "x is: ", x

    toTest(8, 2)
    toTest2(1)

    echo coveragePercentageByFile()
    echo "TOTAL Coverage: ", totalCoverage()
