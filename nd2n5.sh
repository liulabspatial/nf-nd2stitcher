#!/bin/bash

export PATH="/groups/scicompsoft/scicompsoft/kawaset_temp:$PATH"
export NXF_JAVA_HOME="/groups/scicompsoft/scicompsoft/kawaset_temp/tools/jdk-17" 
cd /groups/scicompsoft/scicompsoft/kawaset_temp/nd2n5

/nrs/scicompsoft/kawaset/Liu/nextflow run ./nd2n5/nd2n5.nf -profile lsf --runtime_opts "-B /nrs/scicompsoft/kawaset/Liu -B /scratch" --inputPath '/nrs/scicompsoft/kawaset/Liu3/40X_cereb_11genes/Channel640_561_488_405_Seq0000.nd2' --outputPath '/nrs/scicompsoft/kawaset/Liu3/output_tif' --bgimg '/nrs/scicompsoft/kawaset/Liu3/40X_cereb_11genes/AVG_DarkFrameFastMode20ms.tif'

