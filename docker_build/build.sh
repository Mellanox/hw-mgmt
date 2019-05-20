#!/bin/bash -e

SCRIPT=`realpath $0`
PWD=`dirname $SCRIPT`
OUTPUT=${PWD}/../output/
if [ ! -d "$OUTPUT" ]; then
    mkdir $OUTPUT
fi
docker build -t docker-deb-builder:stretsh -f ${PWD}/dockerfile_hw_mgmt ${PWD}/
docker run -it -v ${PWD}/../:/source-ro:ro -v ${OUTPUT}:/output -v ${PWD}/build-helper.sh:/build-helper.sh:ro -e USER=5616 -e GROUP=101 --rm  docker-deb-builder:stretsh /build-helper.sh
cd ${OUTPUT}
echo $(pwd)/$(ls)
