#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// path to the TIFF series
params.inputPath = ""

// path to the output n5
params.outputPath = ""

params.baseimg = ""

params.bgimg = "/nrs/scicompsoft/kawaset/Liu/AVG_DarkFrameStandardMode50ms.tif"

// path to the scripts
params.scriptPath = "/nrs/scicompsoft/kawaset/nf-demos"

// path to the output dataset
params.outputDataset = "/s0"

// chunk size for n5
params.blockSize = "512,512,256"

// config for running single process
params.mem_gb = "660"
params.cpus = 48
//params.mem_gb = "80"
//params.cpus = 8

// config for running on cluster
params.numWorkers = 8

params.spark_local_dir = null
params.spark_cluster = true
params.spark_workers = 16
params.spark_worker_cores = 12
params.spark_gb_per_core = 14
params.spark_driver_cores = 4
params.spark_driver_memory = '48 GB'

include { getOptions } from '../utils' 

include { SPARK_START         } from '../subworkflows/bits/spark_start/main'
include { SPARK_STOP          } from '../subworkflows/bits/spark_stop/main'

include { SPARK_START as SPARK_START2 } from '../subworkflows/bits/spark_start/main'
include { SPARK_STOP as SPARK_STOP2 } from '../subworkflows/bits/spark_stop/main'

include { STITCHING_PREPARE } from './reusables'
include { STITCHING_PREPARE as STITCHING_PREPARE2 } from './reusables'

process define_dataset {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-fiji:0.0.1'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    /entrypoint.sh define -i $infile -o $outfile -t 2
    """
}

process fix_n5xml {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-py:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    /entrypoint.sh fix_n5xml -i $infile -o $outfile
    """
}

process calc_stitching {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-fiji:0.0.1'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    tuple val(meta), path(files), val(spark)
    val(done) 

    output:
    path(files)
    //tuple val(meta), path(files), val(spark), emit: acquisitions
    
    script:
    inxml = meta.resave_outxml
    """
    /entrypoint.sh calc_stitch -i $inxml -m ${params.mem_gb}G  > /dev/null 2>&1
    """
}
/*
process calc_stitching {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-fiji:0.0.1'
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    val infile

    output:
    val "${infile}"
    
    script:
    """
    /entrypoint.sh calc_stitch -i $infile -m ${params.mem_gb}G
    """
}
*/

process gen_csv {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-py:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar)

    output:
    val "${tar}"
    
    script:
    """
    /entrypoint.sh nd2tiffcsv -i $src -o $tar
    """
}

process split_xml {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-py:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar), val(csv)
    val(control_1) 

    output:
    val "${csv}"
    
    script:
    """
    /entrypoint.sh nd2tiffxml -i $src -o $tar -c $csv
    """
}

process nd2tiff {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-py:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "16 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar), val(bg)

    output:
    val("process_complete"), emit: control_1
    
    script:
    """
    /entrypoint.sh nd2tiff -i $src -o $tar -b $bg
    """
}

process resave {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-fiji:0.0.1'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    tuple val(infile), val(outfile)
    val(control_1) 

    output:
    val "${outfile}"
    
    script:
    """
    /entrypoint.sh resave -i $infile -o $outfile -t ${params.cpus}
    """
}

process SPARK_RESAVE {
    tag "${meta.id}"
    container 'registry.int.janelia.org/liulab/bigstitcher-spark:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }
    cpus { spark.driver_cores }
    memory { spark.driver_memory }

    input:
    tuple val(meta), path(xml), val(spark)

    output:
    tuple val(meta), path(xml), val(spark), emit: acquisitions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    extra_args = task.ext.args ?: ''
    executor_memory = spark.executor_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    driver_memory = spark.driver_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    inxml = meta.resave_inxml
    outxml = meta.resave_outxml
    n5dir = meta.resave_n5dir
    """
    /opt/scripts/runapp.sh "$workflow.containerEngine" "$spark.work_dir" "$spark.uri" \
        /app/app.jar net.preibisch.bigstitcher.spark.ResaveN5 \
        $spark.parallelism $spark.worker_cores "$executor_memory" $spark.driver_cores "$driver_memory" \
        -x ${inxml} -xo ${outxml} -o ${n5dir} --blockSize 512,512,128 -ds 1,1,1

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spark: \$(cat /opt/spark/VERSION)
        stitching-spark: \$(cat /app/VERSION)
    END_VERSIONS
    """
}

process SPARK_DOWNSAMPLE {
    tag "${meta.id}"
    container 'registry.int.janelia.org/liulab/bigstitcher-spark:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }
    cpus { spark.driver_cores }
    memory { spark.driver_memory }

    input:
    tuple val(meta), path(xml), val(spark)

    output:
    tuple val(meta), path(xml), val(spark), emit: acquisitions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    extra_args = task.ext.args ?: ''
    executor_memory = spark.executor_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    driver_memory = spark.driver_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    inxml = meta.fusion_outxml
    outxml = meta.ds_outxml
    n5dir = meta.ds_n5dir
    """
    /opt/scripts/runapp.sh "$workflow.containerEngine" "$spark.work_dir" "$spark.uri" \
        /app/app.jar net.preibisch.bigstitcher.spark.ResaveN5 \
        $spark.parallelism $spark.worker_cores "$executor_memory" $spark.driver_cores "$driver_memory" \
        -x ${inxml} -xo ${outxml} -o ${n5dir} --blockSize 512,512,128 -ds "1,1,1;2,2,1;2,2,2;2,2,2;2,2,2"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spark: \$(cat /opt/spark/VERSION)
        stitching-spark: \$(cat /app/VERSION)
    END_VERSIONS
    """
}

process SPARK_FUSION {
    tag "${meta.id}"
    container 'registry.int.janelia.org/liulab/bigstitcher-spark:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath]) }
    cpus { spark.driver_cores }
    memory { spark.driver_memory }

    input:
    tuple val(meta), path(xml), val(spark) 

    output:
    tuple val(meta), path(xml), val(spark), emit: acquisitions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    extra_args = task.ext.args ?: ''
    executor_memory = spark.executor_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    driver_memory = spark.driver_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    inxml = meta.resave_outxml
    outxml = meta.fusion_outxml
    n5dir = meta.fusion_n5dir
    """
    /opt/scripts/runapp.sh "$workflow.containerEngine" "$spark.work_dir" "$spark.uri" \
        /app/app.jar net.preibisch.bigstitcher.spark.AffineFusion \
        $spark.parallelism $spark.worker_cores "$executor_memory" $spark.driver_cores "$driver_memory" \
        --bdv 0,0 -x ${inxml} -xo ${outxml} -o ${n5dir} --blockSize 512,512,128 --UINT16 --minIntensity 0.0 --maxIntensity 65535.0

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spark: \$(cat /opt/spark/VERSION)
        stitching-spark: \$(cat /app/VERSION)
    END_VERSIONS
    """
}

process fix_res {
    container 'registry.int.janelia.org/liulab/nd2-to-n5-py:0.0.3'
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(dst)

    output:
    val("process_complete"), emit: control_1
    
    script:
    """
    /entrypoint.sh fix_res -i $src -o $dst
    """
}

process remove_dir {
    containerOptions { getOptions([params.inputPath, params.outputPath]) }

    memory { "16 GB" }
    cpus { 2 }

    input:
    val(tar)
    val(control_1) 

    output:
    val "${tar}"
    
    script:
    """
    rm -rf $tar
    """
}

workflow {
    infile = params.inputPath
    indir = file(params.inputPath).parent
    outdir = params.outputPath
    tmpdir = params.outputPath + "/tmp"
    sparkdir = params.outputPath + "/spark"
    bgpath = params.bgimg

    myDir = file(outdir)
    result = myDir.mkdir()
    println result ? "Created $myDir" : "Cannot create directory: $myDir"
    myDir2 = file(tmpdir)
    result2 = myDir2.mkdir()
    println result2 ? "Created $myDir2" : "Cannot create directory: $myDir2"

    bg = Channel.fromPath(bgpath).first()
    nd2 = Channel.fromPath(infile)
    base_name = file(infile).getBaseName()
    nd2.subscribe { println "nd2: $it" }

    param_t = nd2.map{ tuple("${infile}", "${tmpdir}/${file(it).baseName}.csv") }
    csv = gen_csv(param_t)
    csv.subscribe { println "csv: $it" }

    csv
    .map { file(it) }
    .set { csvfile }

    csvfile
    .splitCsv(header:false)
    .map { row-> row[0] }
    .set { flist }

    param_tif = flist.map{ tuple("${infile}", "${it}", "${bgpath}") }
    tiff1 = nd2tiff(param_tif)
    
    param = nd2.map{ tuple("${infile}", "${tmpdir}/${file(it).baseName}.xml") }
    n5xml = define_dataset(param)
    n5xml.subscribe { println "n5xml: $it" }

    param2 = n5xml.map{ tuple("$it", "${tmpdir}/${file(it).baseName}_fixed.xml") }
    fixedxml = fix_n5xml(param2)
    fixedxml.subscribe { println "fixedxml: $it" }

    param_t = fixedxml.map{ tuple("$it", "${tmpdir}/${file(it).baseName}_tiff.xml", "${tmpdir}/${file(it).baseName}_tiff.csv") }
    csv2 = split_xml(param_t, nd2tiff.out.control_1.collect())
    csv2.subscribe { println "csv2: $it" }

    csv2
    .map { file(it) }
    .set { csvfile2 }

    csvfile2
    .splitCsv(header:false)
    .map { row-> row[0] }
    .set { flist2 }

    flist2.subscribe { println "flist2: $it" }

    flist2.map {
        def xml = it
        meta = [:]
        meta.id = file(xml).baseName
        meta.spark_work_dir = "${tmpdir}/spark/${workflow.sessionId}/${meta.id}"
        meta.outdir = outdir
        meta.tmpdir = tmpdir
        meta.resave_inxml = xml
        meta.resave_outxml = meta.outdir + "/" + meta.id + "_resaved.xml"
        meta.resave_n5dir = meta.outdir + "/" + meta.id + "_resaved.n5"
        [meta, xml]
    }.set { ch_acquisitions }

    STITCHING_PREPARE(
        ch_acquisitions
    )

    SPARK_START(
        STITCHING_PREPARE.out, 
        [indir, outdir], //directories to mount
        params.spark_cluster,
        params.spark_workers as int,
        params.spark_worker_cores as int,
        params.spark_gb_per_core as int,
        params.spark_driver_cores as int,
        params.spark_driver_memory
    )

    SPARK_RESAVE(SPARK_START.out)
    done = SPARK_STOP(SPARK_RESAVE.out.acquisitions)

    calc_results = calc_stitching(SPARK_RESAVE.out.acquisitions, done)
    calc_results.map {
        def xml = it
        meta = [:]
        meta.id = file(xml).baseName + "_resaved"
        meta.spark_work_dir = "${tmpdir}/spark/${workflow.sessionId}/${meta.id}"
        meta.outdir = outdir
        meta.tmpdir = tmpdir
        meta.resave_inxml = xml
        meta.resave_outxml = meta.outdir + "/" + meta.id + ".xml"
        meta.resave_n5dir = meta.outdir + "/" + meta.id + ".n5"
        meta.fusion_outxml = meta.tmpdir + "/" + file(xml).baseName + "_fused.xml"
        meta.fusion_n5dir = meta.tmpdir + "/" + file(xml).baseName + "_fused.n5"
        meta.ds_outxml = meta.tmpdir + "/" + file(xml).baseName + "_ds.xml"
        meta.ds_n5dir = meta.tmpdir + "/" + file(xml).baseName + "_ds.n5"
        [meta, xml]
    }.set { ch_acquisitions2 }


    STITCHING_PREPARE2(
        ch_acquisitions2
    )

    SPARK_START2(
        STITCHING_PREPARE2.out, 
        [indir, outdir], //directories to mount
        params.spark_cluster,
        params.spark_workers as int,
        params.spark_worker_cores as int,
        params.spark_gb_per_core as int,
        params.spark_driver_cores as int,
        params.spark_driver_memory
    )

    SPARK_FUSION(SPARK_START2.out)
    SPARK_DOWNSAMPLE(SPARK_FUSION.out.acquisitions)

    done = SPARK_STOP2(SPARK_DOWNSAMPLE.out.acquisitions)

    param5 = SPARK_DOWNSAMPLE.out.acquisitions.map{ tuple("${it[0].ds_outxml}", "${outdir}/easi") }
    fix_res(param5)

    tmpdir_ch = Channel.fromPath(tmpdir)
    remove_dir(tmpdir_ch, fix_res.out.control_1.collect())
}
