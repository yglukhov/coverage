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

type CovData* = tuple[lineNo: int, passes: int]
type CovChunk* = seq[CovData]
var coverageResults = initTable[string, seq[ptr CovChunk]]()

proc registerCovChunk(fileName: string, chunk: var CovChunk) =
    if coverageResults.getOrDefault(fileName).len == 0:
        when defined(js):
            var s : seq[ptr CovChunk]
            {.emit: "`s` = [`chunk`[`chunk`_Idx]];".}
            coverageResults[fileName] = s
        else:
            coverageResults[fileName] = @[addr chunk]
    else:
        when defined(js):
            var s = coverageResults[fileName]
            {.emit: "`s`.push(`chunk`[`chunk`_Idx]);".}
            coverageResults[fileName] = s
        else:
            coverageResults[fileName].add(addr chunk)

proc transform(n, track, list: NimNode): NimNode {.compileTime.} =
    result = copyNimNode(n)
    for c in n.children:
        result.add c.transform(track, list)

    if n.kind in {nnkElifBranch, nnkOfBranch, nnkExceptBranch, nnkElse}:
        let lineno = result[^1].lineNumber

        template trackStmt(track, i) =
            inc track[i].passes

        result[^1] = newStmtList(getAst trackStmt(track, list.len), result[^1])
        template tup(lineno) =
              (lineno, 0)
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
                newCall(bindSym "registerCovChunk", newStrLitNode(file), trackSym)
            )

        result = transform(body, trackSym, trackList)
        result = newStmtList(listVar, result)

when defined(js):
    proc derefChunk(dest: var CovChunk, src: ptr CovChunk) =
        {.emit: """
        `dest`[`dest`_Idx] = `src`;
        """.}
else:
    template derefChunk(dest: var CovChunk, src: ptr CovChunk) =
        shallowCopy(dest, src[])

proc coveredLinesInFile*(fileName: string): seq[CovData] =
    result = newSeq[CovData]()
    var tmp : seq[ptr CovChunk]
    shallowCopy(tmp, coverageResults[fileName])
    for i in 0 ..< tmp.len:
        var covChunk : CovChunk
        derefChunk(covChunk, tmp[i])
        result = result.concat(covChunk)
    result.sort(proc (a, b: CovData): int = cmp(a.lineNo, b.lineNo))

    var newRes = newSeq[CovData](result.len)
    # Deduplicate lines
    var j = 0
    var lastLine = 0
    for i in 0 ..< result.len:
        if result[i].lineNo == lastLine:
            if result[i].passes == 0:
                newRes[j - 1].passes = 0
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
        for i in 0 ..< v.len:
            var covChunk : CovChunk
            derefChunk(covChunk, v[i])
            for data in covChunk:
                inc linesTracked
                if data.passes != 0: inc linesCovered
        result[k] = (linesTracked, linesCovered)

proc coveragePercentageByFile*(): Table[string, float] =
    result = initTable[string, float]()
    for k, v in coverageInfoByFile():
        result[k] = v.linesCovered.float / v.linesTracked.float

proc totalCoverage*(): float =
    var linesTracked = 0
    var linesCovered = 0
    for k, v in coverageResults:
        for i in 0 ..< v.len:
            var covChunk : CovChunk
            derefChunk(covChunk, v[i])
            for data in covChunk:
                inc linesTracked
                if data.passes != 0: inc linesCovered
    result = linesCovered.float / linesTracked.float

when not defined(js) and not defined(emscripten):
    import os, osproc
    import json
    import httpclient
    import md5

    proc initCoverageDir*(path: string = ".") =
        putEnv("NIM_COVERAGE_DIR", path)

    proc saveCovResults() {.noconv.} =
        let jCov = newJObject()
        for k, v in coverageResults:
            let jChunks = newJArray()
            for chunk in v:
                let jChunk = newJArray()
                for ln in chunk[]:
                    let jLn = newJArray()
                    jLn.add(newJInt(ln.lineNo))
                    jLn.add(newJInt(ln.passes))
                    jChunk.add(jLn)
                jChunks.add(jChunk)
            jCov[k] = jChunks
        var i = 0
        while true:
            let covFile = getEnv("NIM_COVERAGE_DIR") / "cov" & $i & ".json"
            if not fileExists(covFile):
                writeFile(covFile, $jCov)
                break
            inc i

    proc getFileSourceCode(p: string): string =
        readFile(p)

    proc expandCovSeqIfNeeded(s: var seq[int], toLen: int) =
        if s.len <= toLen:
            let oldLen = s.len
            s.setLen(toLen + 1)
            for i in oldLen .. toLen:
                s[i] = -1

    proc createCoverageReport*() =
        let covDir = getEnv("NIM_COVERAGE_DIR")
        var i = 0

        var covData = initTable[string, seq[int]]()

        while true:
            let covFile = getEnv("NIM_COVERAGE_DIR") / "cov" & $i & ".json"
            if not fileExists(covFile):
                break
            inc i
            let jf = parseJson(readFile(covFile))
            for fileName, chunks in jf:
                if fileName notin covData:
                    covData[fileName] = @[]

                for chunk in chunks:
                    for ln in chunk:
                        let lineNo = int(ln[0].num)
                        let passes = int(ln[1].num)
                        expandCovSeqIfNeeded(covData[fileName], lineNo)
                        if covData[fileName][lineNo] == -1:
                            covData[fileName][lineNo] = 0
                        covData[fileName][lineNo] += passes
            removeFile(covFile)

        let jCovData = newJObject()
        for k, v in covData:
            let arr = newJArray()
            for i in v: arr.add(%i)
            let d = newJObject()
            d["l"] = arr
            d["s"] = % getFileSourceCode(k)
            jCovData[k] = d

        const htmlTemplate = staticRead("coverageTemplate.html")
        writeFile(getEnv("NIM_COVERAGE_DIR") / "cov.html", htmlTemplate.replace("$COV_DATA", $jCovData))

    if getEnv("NIM_COVERAGE_DIR").len > 0:
        addQuitProc(saveCovResults)

    proc md5OfFile(path: string): string = $getMD5(readFile(path))

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
                    jLines.add(newJInt(data.passes))
                    inc curLine
                var jFile = newJObject()
                jFile["name"] = newJString(relativePath / k)
                jFile["coverage"] = jLines
                jFile["source_digest"] = newJString(md5OfFile(k))
                #jFile["source"] = newJString(readFile(k))
                files.add(jFile)
            request["source_files"] = files
            var data = newMultipartData()
            echo "COVERALLS REQUEST: ", $request
            data["json_file"] = ("file.json", "application/json", $request)
            echo "COVERALLS RESPONSE: ", postContent("https://coveralls.io/api/v1/jobs", multipart=data)
