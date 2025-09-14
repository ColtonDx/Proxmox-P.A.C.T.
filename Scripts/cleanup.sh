source ./workingdir/Options.ini

qm destroy $((nVMID + 1))
qm destroy $((nVMID + 2))
qm destroy $((nVMID + 3))
qm destroy $((nVMID + 11))
qm destroy $((nVMID + 12))
qm destroy $((nVMID + 21))
qm destroy $((nVMID + 22))
qm destroy $((nVMID + 31))
qm destroy $((nVMID + 41))

rm -r ./workingdir
