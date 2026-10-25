# Compile the harness and capture together so Berry resolves their shared symbols.
var source = open("test_solarapp.be", "r")
var harness = source.read()
source.close()
source = open("capture_frames.be.inc", "r")
var capture = source.read()
source.close()
compile(harness + "\n" + capture)()
