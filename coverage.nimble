version = "0.1.0"
author = "Yuriy Glukhov"
description = "Code coverage library for Nim"
license = "MIT"
bin = @["nimcoverage"]

installFiles = @["coverageTemplate.html", "coverage.nim"]

# Deps
requires "nim >= 0.10.0"
requires "nake"
