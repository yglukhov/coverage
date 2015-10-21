import nake

task defaultTask, "Build and run":
    for nimFile in walkFiles "*.nim":
        if nimFile != "nakefile.nim":
            echo "Running: ", nimFile
            direShell nimExe, "c", "--run", "-d:ssl", nimFile
