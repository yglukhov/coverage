import macros
import tables
import strutils
import sequtils
import algorithm

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
type CovChunk* = seq[CovData]
var coverageResults* = initTable[string, seq[ptr CovChunk]]()

proc registerCovChunk*(fileName: string, chunk: var CovChunk) =
    if coverageResults.getOrDefault(fileName).isNil:
        coverageResults[fileName] = @[addr chunk]
    else:
        coverageResults[fileName].add(addr chunk)

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
                newCall("registerCovChunk", newStrLitNode(file), trackSym)
            )

    result = transform(body, trackSym, trackList)
    result = newStmtList(listVar, result)

proc coveredLinesInFile*(fileName: string): seq[CovData] =
    result = newSeq[CovData]()
    for chunk in coverageResults[fileName]:
        result = result.concat(chunk[])
    result.sort(proc (a, b: CovData): int = cmp(a.lineNo, b.lineNo))

    var newRes = newSeq[CovData](result.len)
    # Deduplicate lines
    var j = 0
    var lastLine = 0
    for i in 0 ..< result.len:
        if result[i].lineNo == lastLine:
            if not result[i].passed:
                newRes[j - 1].passed = false
        else:
            lastLine = result[i].lineNo
            newRes[j] = result[i]
            inc j
    newRes.setLen(j)
    shallowCopy(result, newRes)

proc coverageInfoByFile*(): Table[string, tuple[linesTracked, linesCovered: int]] =
    result = initTable[string, tuple[linesTracked, linesCovered: int]]()
    for k, v in coverageResults:
        var linesTracked = 0
        var linesCovered = 0
        for chunk in v:
            for data in chunk[]:
                inc linesTracked
                if data.passed: inc linesCovered
        result[k] = (linesTracked, linesCovered)

proc coveragePercentageByFile*(): Table[string, float] =
    result = initTable[string, float]()
    for k, v in coverageInfoByFile():
        result[k] = v.linesCovered.float / v.linesTracked.float

proc totalCoverage*(): float =
    var linesTracked = 0
    var linesCovered = 0
    for k, v in coverageResults:
        for chunk in v:
            for data in chunk[]:
                inc linesTracked
                if data.passed: inc linesCovered
    result = linesCovered.float / linesTracked.float

when not defined(js):
    import os, osproc
    import json
    import httpclient

    proc sendCoverageResultsToCoveralls*() =
        var request = newJObject()
        if existsEnv("TRAVIS_JOB_ID"):
            request["service_name"] = newJString("travis-ci")
            request["service_job_id"] = newJString(getEnv("TRAVIS_JOB_ID"))

            # Assume we're in git repo. Paths to sources should be relative to
            # repo root
            let gitRes = execCmdEx("git rev-parse --show-toplevel")
            if gitRes.exitCode != 0:
                raise newException(Exception, "GIT Error")

            let curDir = getCurrentDir()

            # TODO: The following is too naive!
            let relativePath = curDir.substr(gitRes.output.len)

            var files = newJArray()
            for k, v in coverageResults:
                let lines = coveredLinesInFile(k)
                var jLines = newJArray()
                var curLine = 1
                for data in lines:
                    while data.lineNo > curLine:
                        jLines.add(newJNull())
                        inc curLine
                    jLines.add(newJInt(if data.passed: 1 else: 0))
                var jFile = newJObject()
                jFile["name"] = newJString(relativePath / k)
                jFile["coverage"] = jLines
                files.add(jFile)
            request["source_files"] = files
            var data = newMultipartData()
            echo "COVERALLS REQUEST: ", $request
            data["json_file"] = ("file.json", "application/json", $request)
            echo "COVERALLS RESPONSE: ", postContent("https://coveralls.io/api/v1/jobs", multipart=data)

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
    echo "COVERED LINES: ", coveredLinesInFile("coverage.nim")
    sendCoverageResultsToCoveralls()
