
include { getOptions } from '../utils' 

process STITCHING_PREPARE {
    tag "${meta.id}"
    label 'process_single'

    input:
    tuple val(meta), path(files)

    output:
    tuple val(meta), path(files)

    script:
    """
    umask 0002
    mkdir -p ${meta.spark_work_dir}
    """
}
