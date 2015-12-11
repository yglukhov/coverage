import nake
import coverage

task defaultTask, "Build and run":
    initCoverageDir()
    for nimFile in walkFiles "*.nim":
        if nimFile != "nakefile.nim":
            echo "Running: ", nimFile
            direShell nimExe, "c", "--run", "-d:ssl", nimFile
            direShell nimExe, "js", "--run", "-d:nodejs", nimFile
    createCoverageReport()
