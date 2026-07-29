nextflow.enable.dsl = 2

process CNVKIT_COVERAGE_TARGET {
    tag "${meta.id}"
    label 'process_medium'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
    publishDir "${params.outdir}/coverage", mode: 'copy', overwrite: true

    input:
    tuple val(meta), path(cram), path(crai)
    path target_bed
    path fasta
    path fai

    output:
    path "${meta.id}.targetcoverage.cnn", emit: target_cnn

    script:
    def mapq_opt  = params.min_mapq   > 0 ? "--min-mapq ${params.min_mapq}" : ""
    def count_opt = params.count_reads     ? "--count"                        : ""
    """
    cnvkit.py coverage \\
        ${cram} \\
        ${target_bed} \\
        -f ${fasta} \\
        ${mapq_opt} \\
        ${count_opt} \\
        -o ${meta.id}.targetcoverage.cnn
    """
}

process CNVKIT_COVERAGE_ANTITARGET {
    tag "${meta.id}"
    label 'process_medium'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
    publishDir "${params.outdir}/coverage", mode: 'copy', overwrite: true

    input:
    tuple val(meta), path(cram), path(crai)
    path antitarget_bed
    path fasta
    path fai

    output:
    path "${meta.id}.antitargetcoverage.cnn", emit: antitarget_cnn

    script:
    def mapq_opt  = params.min_mapq   > 0 ? "--min-mapq ${params.min_mapq}" : ""
    def count_opt = params.count_reads     ? "--count"                        : ""
    """
    cnvkit.py coverage \\
        ${cram} \\
        ${antitarget_bed} \\
        -f ${fasta} \\
        ${mapq_opt} \\
        ${count_opt} \\
        -o ${meta.id}.antitargetcoverage.cnn
    """
}
